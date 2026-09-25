# SPDX-FileCopyrightText: 2026 icefields
# SPDX-License-Identifier: GPL-3.0-only
"""user JSON -> UserEntity row.

Dropped per Field Mapping (no UserEntity column — silent, by design):
has_art (the art URL string carries everything the UI needs),
validation, link. `auth` is a LIVE SESSION TOKEN and is NEVER persisted
outside SessionEntity — dropped, deliberate. fullname_public/disabled
are JSON booleans stored as 0/1 INTEGERs (Room-era schema). serverUrl
and multiUserId are DB-layer columns the response never carries —
written as '' like every other mapper."""


def mapUser(user: dict) -> dict:
    return {
        "id": user.get("id") or "",
        "username": user.get("username") or "",
        "email": user.get("email") or "",
        "access": int(user.get("access") or 0),
        "streamToken": user.get("streamtoken") or "",
        "fullNamePublic": 1 if user.get("fullname_public") else 0,
        "fullName": user.get("fullname") or "",
        "disabled": 1 if user.get("disabled") else 0,
        "createDate": int(user.get("create_date") or 0),
        "lastSeen": int(user.get("last_seen") or 0),
        "website": user.get("website") or "",
        "state": user.get("state") or "",
        "city": user.get("city") or "",
        "art": user.get("art") or "",
        "serverUrl": "",
        "multiUserId": "",
    }
