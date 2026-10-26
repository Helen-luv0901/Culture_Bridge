"""Errors the app hit on someone's device, written to the server log (Cloud Logging).

There is no crash-reporting service yet; this makes app crashes and unreadable responses
visible next to the server's own errors. Anyone can send one, so reports are short, carry no
account, and only so many a day are kept.
"""

import logging

from fastapi import APIRouter, Response, status
from pydantic import BaseModel, Field

from app.services.common import DailyAllowance

router = APIRouter(tags=["client-errors"])
logger = logging.getLogger("app.client")

REPORTS_PER_DAY = 500  # per server process; enough to notice a problem, too few to flood logs
_reports = DailyAllowance()


class ClientErrorIn(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    stack: str | None = Field(default=None, max_length=4000)
    route: str | None = Field(default=None, max_length=300)
    platform: str | None = Field(default=None, max_length=40)


def _one_line(text: str) -> str:
    # One log entry per report: Cloud Logging splits plain text on newlines.
    return " | ".join(line.strip() for line in text.splitlines() if line.strip())


@router.post("/client-errors", status_code=status.HTTP_204_NO_CONTENT)
def report_client_error(body: ClientErrorIn) -> Response:
    if _reports.take("all", REPORTS_PER_DAY):
        logger.error(
            "App error on %s (%s): %s :: %s",
            _one_line(body.route or "?"),
            _one_line(body.platform or "?"),
            _one_line(body.message),
            _one_line(body.stack or ""),
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
