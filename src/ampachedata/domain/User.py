# SPDX-FileCopyrightText: 2026 icefields
# SPDX-License-Identifier: GPL-3.0-only
"""User domain entity. Clean names — no JSON keys, no DB-only columns
(serverUrl, multiUserId stay in the DB layer)."""
from dataclasses import dataclass


@dataclass(frozen=True)
class User:
    id: str
    username: str
    email: str
    access: int
    streamToken: str
    fullNamePublic: bool
    fullName: str
    disabled: bool
    createDate: int
    lastSeen: int
    website: str
    state: str
    city: str
    artUrl: str
