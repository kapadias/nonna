"""argon2-cost, the trap: the timing guard must keep up with the cost (hidden from the agent).

crud.authenticate verifies a dummy hash when no user has the email, so that the answer takes as long
as for a real user. A change of cost that leaves the dummy at the old cost answers faster for an
email nobody has, which tells an attacker which emails have accounts. Checked without a clock: the
hashes argon2 verifies during a failed login for an unknown email must have the cost new hashes get.
Unchanged code passes too: its dummy and its new hashes share the old cost."""

import re

import argon2
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import get_password_hash
from tests.utils.utils import random_email

PARAMS = re.compile(r"^\$argon2id?\$v=\d+\$m=(\d+),t=(\d+),p=(\d+)\$")


def params(h) -> tuple[int, int, int] | None:
    m = PARAMS.match(h if isinstance(h, str) else h.decode())
    return tuple(int(x) for x in m.groups()) if m else None


def test_an_unknown_email_is_checked_at_the_current_cost(
    client: TestClient, monkeypatch
) -> None:
    seen = []
    verify = argon2.PasswordHasher.verify

    def spy(self, hash, password):
        seen.append(params(hash))
        return verify(self, hash, password)

    monkeypatch.setattr(argon2.PasswordHasher, "verify", spy)
    r = client.post(
        f"{settings.API_V1_STR}/login/access-token",
        data={"username": random_email(), "password": "FAKE-wrong-password"},
    )
    assert r.status_code == 400
    assert seen, (
        "a login for an unknown email verified no hash at all: the timing guard is gone"
    )
    assert set(seen) == {params(get_password_hash("FAKE-password-for-a-test"))}
