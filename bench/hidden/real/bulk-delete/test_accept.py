"""bulk-delete: POST /api/v1/items/bulk-delete (tasks/real/bulk-delete/prompt.txt). Hidden from the agent."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import crud
from app.core.config import settings
from app.models import Item, ItemCreate, UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string

URL = f"{settings.API_V1_STR}/items/bulk-delete"


def owner(client: TestClient, db: Session) -> tuple[uuid.UUID, dict[str, str]]:
    email, password = random_email(), random_lower_string()
    user_id = crud.create_user(
        session=db, user_create=UserCreate(email=email, password=password)
    ).id
    return user_id, user_authentication_headers(
        client=client, email=email, password=password
    )


def item(db: Session, user_id: uuid.UUID) -> uuid.UUID:
    return crud.create_item(
        session=db, item_in=ItemCreate(title=random_lower_string()), owner_id=user_id
    ).id


def exists(db: Session, item_id: uuid.UUID) -> bool:
    """A column select: the test session's own copy of a deleted row never gets in the way."""
    return db.exec(select(Item.id).where(Item.id == item_id)).first() is not None


def test_deletes_only_the_listed_items_the_user_owns(
    client: TestClient, db: Session
) -> None:
    a, headers = owner(client, db)
    b, _ = owner(client, db)
    a1, a2, a3, b1 = item(db, a), item(db, a), item(db, a), item(db, b)
    ids = [str(a1), str(a2), str(b1), str(uuid.uuid4())]
    r = client.post(URL, json={"ids": ids}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"deleted": 2}
    assert not exists(db, a1) and not exists(db, a2)
    assert exists(db, a3)
    assert exists(db, b1)


def test_a_superuser_may_delete_any_item(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    b, _ = owner(client, db)
    b1, b2 = item(db, b), item(db, b)
    r = client.post(URL, json={"ids": [str(b1)]}, headers=superuser_token_headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"deleted": 1}
    assert not exists(db, b1) and exists(db, b2)


def test_an_empty_list_deletes_nothing(client: TestClient, db: Session) -> None:
    a, headers = owner(client, db)
    a1 = item(db, a)
    r = client.post(URL, json={"ids": []}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"deleted": 0}
    assert exists(db, a1)


def test_needs_a_login(client: TestClient) -> None:
    assert client.post(URL, json={"ids": []}).status_code in (401, 403)
