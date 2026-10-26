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
        # Per instance, plus app.core.usage's 2. Cloud SQL db-f1-micro allows about 25
        # connections (a few reserved), and during a deploy the old and new revisions can each
        # run two instances next to the jobs. A request waits at most 15 s for one; idle ones
        # are closed after 5 minutes so an instance that went quiet gives them back.
        pool_size=3,
        max_overflow=2,
        pool_recycle=300,
        pool_timeout=15,
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
