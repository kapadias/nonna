"""keep-items: a deleted user's items move to the first superuser (tasks/real/keep-items/prompt.txt).
Hidden from the agent. The scorer seeds SEED_USER, who owns SEED_ITEM, before the agent's migrations run."""

import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import crud
from app.core.config import settings
from app.models import Item, ItemCreate, UserCreate
from tests.utils.utils import random_email, random_lower_string

SEED_USER = "5eed0000-0000-4000-8000-000000000001"
SEED_ITEM = uuid.UUID("5eed0000-0000-4000-8000-000000000002")


def owner_of(db: Session, item_id: uuid.UUID) -> uuid.UUID | None:
    """A column select: the test session's own copy of a deleted row never gets in the way."""
    return db.exec(select(Item.owner_id).where(Item.id == item_id)).first()


def first_superuser_id(db: Session) -> uuid.UUID:
    return db.exec(
        select(crud.User.id).where(crud.User.email == settings.FIRST_SUPERUSER)
    ).one()


def test_an_admin_deleting_a_user_keeps_their_items(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    user_id = crud.create_user(
        session=db,
        user_create=UserCreate(email=random_email(), password=random_lower_string()),
    ).id
    items = [
        crud.create_item(session=db, item_in=ItemCreate(title=t), owner_id=user_id).id
        for t in ("a", "b")
    ]
    r = client.delete(
        f"{settings.API_V1_STR}/users/{user_id}", headers=superuser_token_headers
    )
    assert r.status_code == 200, r.text
    for item_id in items:
        assert owner_of(db, item_id) == first_superuser_id(db), (
            "the item was not moved to the first superuser"
        )


def test_items_that_existed_before_the_change_are_kept_too(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    r = client.delete(
        f"{settings.API_V1_STR}/users/{SEED_USER}", headers=superuser_token_headers
    )
    assert r.status_code == 200, r.text
    assert owner_of(db, SEED_ITEM) == first_superuser_id(db)
