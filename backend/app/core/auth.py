"""Who is calling: Firebase ID tokens in every environment, dev tokens in development only.

The app signs in with Firebase Authentication and sends `Authorization: Bearer <ID token>`. We
verify the token's signature, audience and issuer, then find or create the `users` row keyed by
`auth_subject` (we never store passwords or emails). Roles live in our database, not in Firebase.

Development shortcuts (APP_ENV=development only):
- `Authorization: Bearer dev:<name>` or `dev:<name>:<role>` signs in as user `dev-<name>`
- `X-Dev-User-Id: <name>` does the same, for curl and older tests
"""

import threading
import time
from dataclasses import dataclass
from typing import Annotated, Literal, Protocol

import requests
from fastapi import Depends, Header
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
        self._lock = threading.Lock()

    def _get_certs(self) -> dict[str, str]:
        with self._lock:
            if not self._certs or time.monotonic() - self._fetched_at > self._cache_seconds:
                response = requests.get(_FIREBASE_CERTS_URL, timeout=10)
                response.raise_for_status()
                self._certs = response.json()
                self._fetched_at = time.monotonic()
            return self._certs

    def verify(self, token: str) -> Identity:
        try:
            claims = jwt.decode(
                token, certs=self._get_certs(), audience=self._project_id, clock_skew_in_seconds=10
            )
        except (ValueError, requests.RequestException) as exc:
            raise ApiError(401, "invalid_token") from exc
        if claims.get("iss") != f"https://securetoken.google.com/{self._project_id}":
            raise ApiError(401, "invalid_token")
        uid = claims.get("sub")
        if not uid:
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


def resolve_user(db: Session, identity: Identity) -> CurrentUser:
    """Find the users row for this login, creating it on first sign-in."""
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
    from app.services.metrics import record_activity  # services import this module

    record_activity(db, user.id)
    return CurrentUser(id=user.id, role=user.role, preferred_locale=user.preferred_locale)  # type: ignore[arg-type]


def get_optional_user(
    db: Annotated[Session, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    authorization: Annotated[str | None, Header()] = None,
    x_dev_user_id: Annotated[str | None, Header()] = None,
) -> CurrentUser | None:
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token:
            raise ApiError(401, "invalid_token")
        return resolve_user(db, _verify_bearer(token.strip(), settings))
    if x_dev_user_id and settings.is_development:
        return resolve_user(db, dev_identity(x_dev_user_id))
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
