"""The terms of use and AI notice: which version is current, and the gate on posting.

Bump TERMS_VERSION whenever /terms (app/static/terms.html) changes in a way people must agree
to again; everyone is then asked once more before their next post or comment.
"""

from sqlalchemy.orm import Session

from app.core.auth import CurrentUser
from app.core.errors import ApiError
from app.models import User

TERMS_VERSION = 1


def require_accepted(db: Session, user: CurrentUser) -> None:
    """Posting and commenting need the current terms; reading, reacting and the rest do not."""
    accepted = db.get(User, user.id)
    if accepted is None or accepted.terms_version != TERMS_VERSION:
        raise ApiError(403, "terms_not_accepted")
