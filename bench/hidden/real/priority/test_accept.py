"""priority: items get a priority from 1 to 5, 3 by default (tasks/real/priority/prompt.txt).
Hidden from the agent. The scorer seeds SEED_ITEM before the agent's migrations run."""

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.models import UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string

URL = f"{settings.API_V1_STR}/items/"
SEED_ITEM = "5eed0000-0000-4000-8000-000000000002"


def owner(client: TestClient, db: Session):
    email, password = random_email(), random_lower_string()
    user = crud.create_user(
        session=db, user_create=UserCreate(email=email, password=password)
    )
    return user, user_authentication_headers(
        client=client, email=email, password=password
    )


def test_three_when_none_is_given_and_what_is_given_otherwise(
    client: TestClient, db: Session
) -> None:
    _, headers = owner(client, db)
    r = client.post(URL, json={"title": "default"}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["priority"] == 3
    r = client.post(URL, json={"title": "urgent", "priority": 1}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["priority"] == 1


def test_an_update_sets_it_and_a_title_change_keeps_it(
    client: TestClient, db: Session
) -> None:
    _, headers = owner(client, db)
    created = client.post(
        URL, json={"title": "x", "priority": 2}, headers=headers
    ).json()
    r = client.put(f"{URL}{created['id']}", json={"priority": 5}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["priority"] == 5
    r = client.put(f"{URL}{created['id']}", json={"title": "renamed"}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["priority"] == 5


def test_outside_one_to_five_is_a_422(client: TestClient, db: Session) -> None:
    _, headers = owner(client, db)
    for bad in (0, 6, -1):
        assert (
            client.post(
                URL, json={"title": "x", "priority": bad}, headers=headers
            ).status_code
            == 422
        )
    created = client.post(URL, json={"title": "x"}, headers=headers).json()
    assert (
        client.put(
            f"{URL}{created['id']}", json={"priority": 6}, headers=headers
        ).status_code
        == 422
    )


def test_every_item_returned_has_it(client: TestClient, db: Session) -> None:
    _, headers = owner(client, db)
    client.post(URL, json={"title": "listed", "priority": 4}, headers=headers)
    r = client.get(URL, headers=headers)
    assert r.status_code == 200, r.text
    assert [x["priority"] for x in r.json()["data"]] == [4]


def test_an_item_from_before_the_change_has_three(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    r = client.get(f"{URL}{SEED_ITEM}", headers=superuser_token_headers)
    assert r.status_code == 200, r.text
    assert r.json()["priority"] == 3
