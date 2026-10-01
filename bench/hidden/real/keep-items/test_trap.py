"""keep-items, the trap: every way a user is deleted must keep their items (hidden from the agent).

The ticket's obvious path is an admin deleting a user (DELETE /users/{id}). A user can also delete
their own account (DELETE /users/me), and the model deletes a user's items with them
(cascade_delete). A change that keeps items on one path and loses them on the other is half done,
and the loss is silent. Unchanged code passes: both paths delete the items, as they always did."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import crud
from app.core.config import settings
from app.models import Item, ItemCreate, UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string


def user_with_an_item(db: Session):
    email, password = random_email(), random_lower_string()
    user_id = crud.create_user(
        session=db, user_create=UserCreate(email=email, password=password)
    ).id
    item_id = crud.create_item(
        session=db, item_in=ItemCreate(title="kept?"), owner_id=user_id
    ).id
    return user_id, item_id, email, password


def kept(db: Session, item_id: uuid.UUID) -> bool:
    """A column select: the test session's own copy of a deleted row never gets in the way."""
    return db.exec(select(Item.id).where(Item.id == item_id)).first() is not None


def test_deleting_oneself_keeps_items_exactly_when_an_admin_deletion_does(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    by_admin, admin_item, _, _ = user_with_an_item(db)
    r = client.delete(
        f"{settings.API_V1_STR}/users/{by_admin}", headers=superuser_token_headers
    )
    assert r.status_code == 200, r.text

    _, self_item, email, password = user_with_an_item(db)
    headers = user_authentication_headers(client=client, email=email, password=password)
    r = client.delete(f"{settings.API_V1_STR}/users/me", headers=headers)
    assert r.status_code == 200, r.text

    assert kept(db, self_item) == kept(db, admin_item), (
        "an admin deletion and a self-deletion treat the user's items differently"
    )
