from fastapi import APIRouter, Response, status

from app.core.auth import RequiredUser
from app.core.db import DbSession
from app.services import actions as svc

router = APIRouter(tags=["procedures"])


@router.get("/actions")
def list_actions(db: DbSession) -> list[svc.ActionSummary]:
    return svc.list_actions(db)


@router.get("/actions/{action_id}")
def get_action(action_id: str, db: DbSession) -> svc.ActionDetail:
    return svc.get_action(db, action_id)


@router.post("/actions/{action_id}/executions")
def start_execution(
    action_id: str, body: svc.StartExecution, user: RequiredUser, db: DbSession, response: Response
) -> svc.ExecutionOut:
    execution, created = svc.start_execution(db, user, action_id, body.identity_type)
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return execution


@router.get("/me/executions")
def my_executions(
    user: RequiredUser, db: DbSession, include_finished: bool = False
) -> list[svc.ExecutionOut]:
    return svc.my_executions(db, user, include_finished)


@router.get("/executions/{execution_id}")
def get_execution(execution_id: str, user: RequiredUser, db: DbSession) -> svc.ExecutionOut:
    return svc.get_execution(db, user, execution_id)


@router.put("/executions/{execution_id}/steps/{step_id}")
def set_step(
    execution_id: str, step_id: str, body: svc.StepUpdate, user: RequiredUser, db: DbSession
) -> svc.ExecutionOut:
    return svc.set_step(db, user, execution_id, step_id, body.state)


@router.post("/executions/{execution_id}/finish")
def finish_execution(
    execution_id: str, body: svc.FinishExecution, user: RequiredUser, db: DbSession
) -> svc.ExecutionOut:
    return svc.finish_execution(db, user, execution_id, body.outcome)


@router.post("/executions/{execution_id}/feedback", status_code=status.HTTP_201_CREATED)
def add_feedback(
    execution_id: str, body: svc.FeedbackIn, user: RequiredUser, db: DbSession
) -> svc.FeedbackOut:
    return svc.add_feedback(db, user, execution_id, body)
