"""Database engine and per-request sessions (Cloud SQL for PostgreSQL)."""

from collections.abc import Iterator
from functools import lru_cache
from typing import Annotated

from fastapi import Depends
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings


@lru_cache
def get_engine() -> Engine:
    # A database that stops answering fails within seconds (and /health says so) instead of hanging.
    return create_engine(
        get_settings().database_url,
        pool_pre_ping=True,
        pool_size=5,
        connect_args={"connect_timeout": 10},
    )


@lru_cache
def get_sessionmaker() -> sessionmaker[Session]:
    return sessionmaker(get_engine(), expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """One session per request. Services commit explicitly; anything uncommitted rolls back."""
    with get_sessionmaker()() as session:
        yield session


DbSession = Annotated[Session, Depends(get_db)]
