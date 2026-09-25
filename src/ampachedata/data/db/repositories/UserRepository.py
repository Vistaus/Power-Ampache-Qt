# SPDX-FileCopyrightText: 2026 icefields
# SPDX-License-Identifier: GPL-3.0-only
"""SQL-only access to UserEntity (PK id). Never sees HTTP.

Transaction semantics: upserts commit only when this call owns the
transaction (none open on the connection). Inside a caller-owned
transaction the commit stays with the caller so multi-repository
write-throughs commit as ONE unit."""
from ....domain.User import User

_COLUMNS = (
    "id", "username", "email", "access", "streamToken", "fullNamePublic",
    "fullName", "disabled", "createDate", "lastSeen", "website", "state",
    "city", "art", "serverUrl", "multiUserId",
)

_UPSERT_SQL = "INSERT OR REPLACE INTO UserEntity ({}) VALUES ({})".format(
    ", ".join(_COLUMNS),
    ", ".join("?" * len(_COLUMNS)),
)

_SELECT_SQL = (
    "SELECT id, username, email, access, streamToken, fullNamePublic, "
    "fullName, disabled, createDate, lastSeen, website, state, city, art "
    "FROM UserEntity"
)


def _toUser(row) -> User:
    return User(
        id=row["id"],
        username=row["username"],
        email=row["email"],
        access=row["access"],
        streamToken=row["streamToken"] or "",
        fullNamePublic=bool(row["fullNamePublic"]),
        fullName=row["fullName"] or "",
        disabled=bool(row["disabled"]),
        createDate=row["createDate"],
        lastSeen=row["lastSeen"],
        website=row["website"] or "",
        state=row["state"] or "",
        city=row["city"] or "",
        artUrl=row["art"] or "",
    )


class UserRepository:
    def __init__(self, database):
        self._database = database

    def upsertUsers(self, rows) -> None:
        # Commits only when this call owns the transaction (none open yet).
        values = [[row[column] for column in _COLUMNS] for row in rows]
        connection = self._database.connection
        ownsTransaction = not connection.in_transaction
        connection.executemany(_UPSERT_SQL, values)
        if ownsTransaction:
            connection.commit()

    def getUser(self, userId):
        """Read-back for the user write-through flow: the UserEntity row
        with this id, or None."""
        row = self._database.connection.execute(
            _SELECT_SQL + " WHERE id = ?", (userId,)
        ).fetchone()
        return _toUser(row) if row is not None else None
