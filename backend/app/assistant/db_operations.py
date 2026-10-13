"""Pending operations stored in assistant_operations, confirmed through the executions service."""

from dataclasses import dataclass
from typing import Any

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.assistant.operations import OPERATION_TTL, OperationError, PendingOperation
from app.core.auth import CurrentUser
from app.core.errors import ApiError
from app.models import AssistantOperation
from app.services import actions
from app.services.common import now

_RETAIN = OPERATION_TTL * 12 * 24  # resolved and expired rows are kept for a day


def _out(row: AssistantOperation) -> PendingOperation:
    return PendingOperation(
        id=row.id,
        user_id=row.user_id,
        type=row.type,  # type: ignore[arg-type]
        target_id=row.target_id,
        summary=row.summary,
        status=row.status,  # type: ignore[arg-type]
        created_at=row.created_at,
        expires_at=row.expires_at,
        result=row.result,
        resolved_at=row.resolved_at,
    )


@dataclass
class DbOperationService:
    db: Session

    def propose_start_action(
        self, user: CurrentUser, action_id: str, summary: str
    ) -> PendingOperation:
        created = now()
        self.db.execute(
            delete(AssistantOperation).where(AssistantOperation.expires_at < created - _RETAIN)
        )
        row = AssistantOperation(
            user_id=user.id,
            type="start_action",
            target_id=action_id,
            summary=summary,
            created_at=created,
            expires_at=created + OPERATION_TTL,
        )
        self.db.add(row)
        self.db.commit()
        return _out(row)

    def _owned(self, operation_id: str, user: CurrentUser | None, lock: bool) -> AssistantOperation:
        if user is None:
            raise OperationError("login_required", 401)
        # FOR UPDATE serializes concurrent confirms of the same operation.
        row = self.db.get(AssistantOperation, operation_id, with_for_update=lock)
        if row is None or row.user_id != user.id:
            raise OperationError("operation_not_found", 404)
        if row.status == "pending" and now() >= row.expires_at:
            self._resolve(row, "expired", None)
        return row

    def _resolve(self, row: AssistantOperation, status: str, result: dict[str, Any] | None):
        row.status = status
        row.result = result
        row.resolved_at = now()
        self.db.commit()

    def get(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        return _out(self._owned(operation_id, user, lock=False))

    def confirm(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        row = self._owned(operation_id, user, lock=True)
        if row.status == "confirmed":
            self.db.commit()
            return _out(row)
        if row.status != "pending":
            self.db.commit()
            raise OperationError(f"operation_{row.status}", 409)
        assert user is not None
        try:
            execution, created = actions.start_execution(self.db, user, row.target_id)
        except ApiError:
            self.db.rollback()
            row = self.db.get(AssistantOperation, operation_id)
            assert row is not None
            self._resolve(row, "failed", {"reason": "action_unavailable"})
            return _out(row)
        row = self.db.get(AssistantOperation, operation_id)
        assert row is not None
        self._resolve(
            row, "confirmed", {"execution_id": execution.id, "already_started": not created}
        )
        return _out(row)

    def cancel(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        row = self._owned(operation_id, user, lock=True)
        if row.status == "cancelled":
            self.db.commit()
            return _out(row)
        if row.status != "pending":
            self.db.commit()
            raise OperationError(f"operation_{row.status}", 409)
        self._resolve(row, "cancelled", None)
        return _out(row)
