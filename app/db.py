from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from .models import Base


class Database:
    def __init__(self, path: Path):
        self.path = path
        self.engine: Engine = create_engine(
            f"sqlite:///{path}",
            connect_args={"check_same_thread": False, "timeout": 30},
            future=True,
        )

        @event.listens_for(self.engine, "connect")
        def _set_sqlite_pragma(dbapi_connection, _connection_record):  # type: ignore[no-untyped-def]
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA synchronous=NORMAL")
            cursor.execute("PRAGMA busy_timeout=30000")
            cursor.close()

        self.session_factory = sessionmaker(
            bind=self.engine, expire_on_commit=False, class_=Session
        )
        Base.metadata.create_all(self.engine)
        self._migrate()

    def _migrate(self) -> None:
        with self.engine.begin() as connection:
            rows = connection.exec_driver_sql("PRAGMA table_info(classification_rules)").fetchall()
            columns = {row[1] for row in rows}
            additions = {
                "direction": "VARCHAR(8)",
                "device": "VARCHAR(40)",
                "title_template": "VARCHAR(200)",
            }
            for name, ddl in additions.items():
                if name not in columns:
                    connection.exec_driver_sql(
                        f"ALTER TABLE classification_rules ADD COLUMN {name} {ddl}"
                    )

    @contextmanager
    def session(self) -> Iterator[Session]:
        session = self.session_factory()
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()


_db: Database | None = None


def init_database(path: Path) -> Database:
    global _db
    _db = Database(path)
    return _db


def get_database() -> Database:
    if _db is None:
        raise RuntimeError("database is not initialised")
    return _db
