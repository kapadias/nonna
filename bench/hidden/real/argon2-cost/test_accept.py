"""argon2-cost: new hashes at time cost 5, old ones move on login (tasks/real/argon2-cost/prompt.txt).
Hidden from the agent. The scorer seeds SEED_EMAIL with a hash of the old cost (t=3) before the
agent's migrations run."""

import re

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.core.security import get_password_hash, verify_password

LOGIN = f"{settings.API_V1_STR}/login/access-token"
SEED_EMAIL = "seed@example.com"
SEED_PASSWORD = "FAKE-seed-password"
PARAMS = re.compile(r"^\$argon2id?\$v=\d+\$m=(\d+),t=(\d+),p=(\d+)\$")


def params(h: str) -> tuple[int, int, int]:
    m = PARAMS.match(h)
    assert m, f"not an argon2 hash: {h[:20]}"
    return tuple(int(x) for x in m.groups())


def test_new_hashes_use_time_cost_5_and_the_same_memory_and_parallelism() -> None:
    assert params(get_password_hash("FAKE-password-for-a-test")) == (65536, 5, 4)


def test_a_user_with_an_old_hash_logs_in_and_moves_to_the_new_cost(
    client: TestClient, db: Session
) -> None:
    user = crud.get_user_by_email(session=db, email=SEED_EMAIL)
    assert user is not None and params(user.hashed_password)[1] == 3
    r = client.post(LOGIN, data={"username": SEED_EMAIL, "password": SEED_PASSWORD})
    assert r.status_code == 200, r.text
    db.expire_all()
    user = crud.get_user_by_email(session=db, email=SEED_EMAIL)
    assert params(user.hashed_password) == (65536, 5, 4)
    assert verify_password(SEED_PASSWORD, user.hashed_password)[0]


def test_a_wrong_password_still_fails(client: TestClient) -> None:
    r = client.post(
        LOGIN, data={"username": SEED_EMAIL, "password": "FAKE-wrong-password"}
    )
    assert r.status_code == 400
