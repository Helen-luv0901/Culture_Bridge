"""Who is calling: Firebase ID tokens in every environment, dev tokens in development only.

The app signs in with Firebase Authentication and sends `Authorization: Bearer <ID token>`. We
verify the token's signature, audience and issuer, then find or create the `users` row keyed by
`auth_subject` (we never store passwords or emails). Roles live in our database, not in Firebase.

Only the sign-in methods in ALLOWED_SIGN_IN_PROVIDERS (Google and Apple) are accepted. If Google's
public keys can't be fetched, the last good keys stay in use; with none at all the answer is 503
auth_unavailable, so the app says "try again" instead of signing the person out.

A suspended account (users.suspended_at, set by an admin) may still read; any other request
(POST, PUT, PATCH, DELETE) answers 403 account_suspended, except deleting the account and asking
for a translation (a read that happens to be a POST). Staff are never held back.

Development shortcuts (APP_ENV=development only):
- `Authorization: Bearer dev:<name>` or `dev:<name>:<role>` signs in as user `dev-<name>`
- `X-Dev-User-Id: <name>` does the same, for curl and older tests
"""

import logging
import re
import threading
import time
from dataclasses import dataclass
from typing import Annotated, Literal, Protocol

import requests
from fastapi import Depends, Header, Request
from google.auth import jwt
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.db import get_db
from app.core.errors import ApiError
from app.models import User

Role = Literal["student", "reviewer", "admin"]
_ROLES = ("student", "reviewer", "admin")
_FIREBASE_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
)
_REFETCH_AFTER_SECONDS = 60
# After a failed key fetch, the old keys are used this long before Google is asked again, so an
# outage doesn't make every request wait on a timeout.
_RETRY_FAILED_FETCH_AFTER_SECONDS = 60
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class CurrentUser:
    id: str
    role: Role = "student"
    preferred_locale: str = "zh-Hant"

    @property
    def is_staff(self) -> bool:
        return self.role in ("reviewer", "admin")


@dataclass(frozen=True)
class Identity:
    subject: str  # stored as users.auth_subject, e.g. "firebase:<uid>"
    user_id: str | None = None  # fixed id for dev users
    role: Role | None = None  # dev users only


class TokenVerifier(Protocol):
    def verify(self, token: str) -> Identity: ...


class FirebaseTokenVerifier:
    """Verifies Firebase ID tokens against Google's rotating public certificates."""

    def __init__(self, project_id: str, cache_seconds: int = 3600) -> None:
        self._project_id = project_id
        self._cache_seconds = cache_seconds
        self._certs: dict[str, str] = {}
        self._fetched_at = 0.0
        self._failed_at = float("-inf")
        self._lock = threading.Lock()

    def _get_certs(self, max_age: float | None = None) -> dict[str, str]:
        with self._lock:
            now = time.monotonic()
            limit = self._cache_seconds if max_age is None else max_age
            if self._certs and now - self._fetched_at <= limit:
                return self._certs
            if now - self._failed_at < _RETRY_FAILED_FETCH_AFTER_SECONDS:
                if self._certs:
                    return self._certs
                # Fetching just failed with nothing cached: answer at once rather than have
                # every request queue on the lock for another 10 s timeout.
                raise ApiError(503, "auth_unavailable")
            try:
                response = requests.get(_FIREBASE_CERTS_URL, timeout=10)
                response.raise_for_status()
                certs = response.json()
                if not isinstance(certs, dict) or not certs:
                    raise ValueError("no keys in the response")
            except (requests.RequestException, ValueError) as exc:
                self._failed_at = now
                if self._certs:
                    logger.warning("Google sign-in keys unavailable, using the last good ones")
                    return self._certs
                logger.error("Google sign-in keys unavailable and none cached: %s", exc)
                raise ApiError(503, "auth_unavailable") from exc
            self._certs = certs
            self._fetched_at = now
            return self._certs

    def _decode(self, token: str, certs: dict[str, str]) -> dict:
        return jwt.decode(token, certs=certs, audience=self._project_id, clock_skew_in_seconds=10)

    def verify(self, token: str) -> Identity:
        try:
            certs = self._get_certs()
            try:
                claims = self._decode(token, certs)
            except ValueError:
                # Google rotates its signing keys; a token signed with a new key fails until
                # the keys are fetched again (at most once a minute, so bad tokens can't force it).
                fresh = self._get_certs(max_age=_REFETCH_AFTER_SECONDS)
                if fresh is certs:
                    raise
                claims = self._decode(token, fresh)
        except (ValueError, requests.RequestException) as exc:
            raise ApiError(401, "invalid_token") from exc
        if claims.get("iss") != f"https://securetoken.google.com/{self._project_id}":
            raise ApiError(401, "invalid_token")
        uid = claims.get("sub")
        if not uid:
            raise ApiError(401, "invalid_token")
        firebase = claims.get("firebase")
        provider = firebase.get("sign_in_provider") if isinstance(firebase, dict) else None
        if provider not in get_settings().allowed_sign_in_providers:
            raise ApiError(401, "invalid_token")
        return Identity(subject=f"firebase:{uid}")


def dev_identity(name: str, role: str | None = None) -> Identity:
    if not name or len(name) > 40 or not name.replace("-", "").replace("_", "").isalnum():
        raise ApiError(401, "invalid_token")
    if role is not None and role not in _ROLES:
        raise ApiError(401, "invalid_token")
    return Identity(subject=f"dev:{name}", user_id=f"dev-{name}", role=role)  # type: ignore[arg-type]


_firebase: dict[str, FirebaseTokenVerifier] = {}


def _verify_bearer(token: str, settings: Settings) -> Identity:
    if token.startswith("dev:"):
        if not settings.is_development:
            raise ApiError(401, "invalid_token")
        parts = token.split(":")
        return dev_identity(parts[1], parts[2] if len(parts) > 2 else None)
    if not settings.firebase_project_id:
        raise ApiError(401, "login_not_configured")
    verifier = _firebase.setdefault(
        settings.firebase_project_id, FirebaseTokenVerifier(settings.firebase_project_id)
    )
    return verifier.verify(token)


def resolve_user(db: Session, identity: Identity, writing: bool = False) -> CurrentUser:
    """Find the users row for this login, creating it on first sign-in.

    writing: the request changes something, which a suspended account may not do."""
    user = db.scalar(select(User).where(User.auth_subject == identity.subject))
    if user is None:
        user = User(auth_subject=identity.subject, role=identity.role or "student")
        if identity.user_id:
            user.id = identity.user_id
        db.add(user)
        try:
            db.commit()
        except IntegrityError:  # two first requests raced; the other one created it
            db.rollback()
            user = db.scalar(select(User).where(User.auth_subject == identity.subject))
            if user is None:
                raise
    elif identity.role and user.role != identity.role:  # dev tokens may switch role
        user.role = identity.role
        db.commit()
    if writing and user.suspended_at is not None and user.role not in ("reviewer", "admin"):
        db.commit()  # hand the connection back
        raise ApiError(403, "account_suspended")
    from app.services.metrics import record_activity  # services import this module

    record_activity(db, user.id)
    # End the read above so the pooled connection goes back now, not after the response: many
    # endpoints then wait up to a minute on Gemini, and five such requests would starve the
    # pool. The session reconnects if the endpoint queries again.
    db.commit()
    return CurrentUser(id=user.id, role=user.role, preferred_locale=user.preferred_locale)  # type: ignore[arg-type]


_READS = ("GET", "HEAD", "OPTIONS")
# Writes a suspended account may still make: deleting itself (always possible, store rule) and
# asking for a translation of a post (a read that is a POST because it may store one).
# A suspended account can still read, protect itself and remove what it published: delete
# the account, its own posts, comments and photo, and block or unblock people. (Each route
# still checks that the thing is theirs.)
_ALWAYS_ALLOWED = (
    ("DELETE", re.compile(r"/api/me")),
    ("POST", re.compile(r"/api/experiences/[^/]+/translations")),
    ("DELETE", re.compile(r"/api/experiences/[^/]+")),
    ("DELETE", re.compile(r"/api/comments/[^/]+")),
    ("DELETE", re.compile(r"/api/me/avatar")),
    ("POST", re.compile(r"/api/(me/)?blocks")),
    ("DELETE", re.compile(r"/api/me/blocks/[^/]+")),
)


def _writes(request: Request) -> bool:
    if request.method in _READS:
        return False
    path = request.url.path.rstrip("/")
    return not any(
        request.method == method and pattern.fullmatch(path) for method, pattern in _ALWAYS_ALLOWED
    )


def get_optional_user(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    authorization: Annotated[str | None, Header()] = None,
    x_dev_user_id: Annotated[str | None, Header()] = None,
) -> CurrentUser | None:
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise ApiError(401, "invalid_token")
        return resolve_user(db, _verify_bearer(token.strip(), settings), _writes(request))
    if x_dev_user_id and settings.is_development:
        return resolve_user(db, dev_identity(x_dev_user_id), _writes(request))
    return None


OptionalUser = Annotated[CurrentUser | None, Depends(get_optional_user)]


def require_user(user: OptionalUser) -> CurrentUser:
    if user is None:
        raise ApiError(401, "login_required")
    return user


RequiredUser = Annotated[CurrentUser, Depends(require_user)]


def require_staff(user: RequiredUser) -> CurrentUser:
    if not user.is_staff:
        raise ApiError(403, "staff_only")
    return user


def require_admin(user: RequiredUser) -> CurrentUser:
    if user.role != "admin":
        raise ApiError(403, "admin_only")
    return user


StaffUser = Annotated[CurrentUser, Depends(require_staff)]
AdminUser = Annotated[CurrentUser, Depends(require_admin)]
