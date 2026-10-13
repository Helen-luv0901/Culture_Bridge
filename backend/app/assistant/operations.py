"""Pending operations: the assistant never writes data directly (work-assignment A-17).

A write request such as "start this procedure for me" becomes a pending operation that expires
after 5 minutes. Only the owner can confirm it, and confirming re-checks login, expiry and the
target before the write runs, exactly once. `OperationService` keeps operations in memory for
unit tests; `db_operations.DbOperationService` stores them in assistant_operations.
"""

import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime, timedelta
from typing import Any, Literal, Protocol

from app.assistant.data import AssistantDataSource, DemoDataSource, ProgressRecord, ProgressStep
from app.core.auth import CurrentUser

OperationType = Literal["start_action"]
OperationStatus = Literal["pending", "confirmed", "cancelled", "expired", "failed"]

OPERATION_TTL = timedelta(minutes=5)
_RETAIN_RESOLVED = timedelta(hours=1)


@dataclass(frozen=True)
class PendingOperation:
    id: str
    user_id: str
    type: OperationType
    target_id: str
    summary: str
    status: OperationStatus
    created_at: datetime
    expires_at: datetime
    result: dict[str, Any] | None = None
    resolved_at: datetime | None = None


class OperationError(Exception):
    def __init__(self, code: str, status_code: int) -> None:
        super().__init__(code)
        self.code = code
        self.status_code = status_code


class OperationStore(Protocol):
    def propose_start_action(
        self, user: CurrentUser, action_id: str, summary: str
    ) -> PendingOperation: ...

    def get(self, operation_id: str, user: CurrentUser | None) -> PendingOperation: ...

    def confirm(self, operation_id: str, user: CurrentUser | None) -> PendingOperation: ...

    def cancel(self, operation_id: str, user: CurrentUser | None) -> PendingOperation: ...


class ExecutionWriter(Protocol):
    def start_execution(self, user_id: str, action_id: str) -> dict[str, Any]: ...


@dataclass
class DemoExecutionWriter:
    """Writes into DemoDataSource.progress so get_my_progress sees the new execution."""

    data: DemoDataSource

    def start_execution(self, user_id: str, action_id: str) -> dict[str, Any]:
        records = self.data.progress.setdefault(user_id, [])
        existing = next((r for r in records if r.action_id == action_id), None)
        if existing:
            return {"execution_id": existing.execution_id, "already_started": True}
        action = self.data.actions[action_id]
        record = ProgressRecord(
            execution_id=uuid.uuid4().hex,
            action_id=action_id,
            action_title=action.title,
            started_at=datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z"),
            steps=tuple(ProgressStep(i, s, "pending") for i, s in enumerate(action.steps, 1)),
        )
        records.append(record)
        return {"execution_id": record.execution_id, "already_started": False}


def _now() -> datetime:
    return datetime.now(UTC)


@dataclass
class OperationService:
    data: AssistantDataSource
    writer: ExecutionWriter
    clock: Callable[[], datetime] = _now
    _items: dict[str, PendingOperation] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def propose_start_action(
        self, user: CurrentUser, action_id: str, summary: str
    ) -> PendingOperation:
        now = self.clock()
        operation = PendingOperation(
            id=uuid.uuid4().hex,
            user_id=user.id,
            type="start_action",
            target_id=action_id,
            summary=summary,
            status="pending",
            created_at=now,
            expires_at=now + OPERATION_TTL,
        )
        with self._lock:
            self._purge(now)
            self._items[operation.id] = operation
        return operation

    def get(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        with self._lock:
            return self._expire_if_due(self._owned(operation_id, user))

    def confirm(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        # The lock spans the write so two confirms of the same operation cannot both write.
        with self._lock:
            operation = self._expire_if_due(self._owned(operation_id, user))
            if operation.status == "confirmed":
                return operation
            if operation.status != "pending":
                raise OperationError(f"operation_{operation.status}", 409)
            if self.data.get_action(operation.target_id) is None:
                return self._resolve(operation, "failed", {"reason": "action_unavailable"})
            result = self.writer.start_execution(operation.user_id, operation.target_id)
            return self._resolve(operation, "confirmed", result)

    def cancel(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        with self._lock:
            operation = self._expire_if_due(self._owned(operation_id, user))
            if operation.status == "cancelled":
                return operation
            if operation.status != "pending":
                raise OperationError(f"operation_{operation.status}", 409)
            return self._resolve(operation, "cancelled", None)

    def _owned(self, operation_id: str, user: CurrentUser | None) -> PendingOperation:
        if user is None:
            raise OperationError("login_required", 401)
        operation = self._items.get(operation_id)
        # Someone else's operation looks exactly like a missing one.
        if operation is None or operation.user_id != user.id:
            raise OperationError("operation_not_found", 404)
        return operation

    def _expire_if_due(self, operation: PendingOperation) -> PendingOperation:
        if operation.status == "pending" and self.clock() >= operation.expires_at:
            return self._resolve(operation, "expired", None)
        return operation

    def _resolve(
        self, operation: PendingOperation, status: OperationStatus, result: dict[str, Any] | None
    ) -> PendingOperation:
        resolved = replace(operation, status=status, result=result, resolved_at=self.clock())
        self._items[operation.id] = resolved
        return resolved

    def _purge(self, now: datetime) -> None:
        stale = [
            key
            for key, op in self._items.items()
            if (op.resolved_at or op.expires_at) + _RETAIN_RESOLVED < now
        ]
        for key in stale:
            del self._items[key]
