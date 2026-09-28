"""csv-export: GET /api/v1/items/export (tasks/real/csv-export/prompt.txt). Hidden from the agent."""

import csv
import io
from datetime import datetime

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.models import ItemCreate, UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string

URL = f"{settings.API_V1_STR}/items/export"


def owner(client: TestClient, db: Session):
    email, password = random_email(), random_lower_string()
    user = crud.create_user(
        session=db, user_create=UserCreate(email=email, password=password)
    )
    return user, user_authentication_headers(
        client=client, email=email, password=password
    )


def rows(text: str) -> list[list[str]]:
    return list(csv.reader(io.StringIO(text)))


def test_exports_own_items_as_csv(client: TestClient, db: Session) -> None:
    a, headers = owner(client, db)
    b, _ = owner(client, db)
    mine = [
        crud.create_item(
            session=db,
            item_in=ItemCreate(title="Plain", description="first"),
            owner_id=a.id,
        ),
        crud.create_item(
            session=db, item_in=ItemCreate(title='Widget, "Pro"'), owner_id=a.id
        ),
    ]
    crud.create_item(session=db, item_in=ItemCreate(title="not mine"), owner_id=b.id)
    r = client.get(URL, headers=headers)
    assert r.status_code == 200, r.text
    assert r.headers["content-type"].startswith("text/csv")
    got = rows(r.text)
    assert got[0] == ["id", "title", "description", "created_at"]
    body = {x[0]: x[1:] for x in got[1:] if x}
    assert set(body) == {str(i.id) for i in mine}
    assert body[str(mine[0].id)][:2] == ["Plain", "first"]
    assert body[str(mine[1].id)][:2] == ['Widget, "Pro"', ""]
    for _, _, created in body.values():
        datetime.fromisoformat(created)


def test_a_superuser_exports_only_their_own(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    a, _ = owner(client, db)
    theirs = crud.create_item(
        session=db, item_in=ItemCreate(title="theirs"), owner_id=a.id
    )
    r = client.get(URL, headers=superuser_token_headers)
    assert r.status_code == 200, r.text
    assert str(theirs.id) not in {x[0] for x in rows(r.text)[1:] if x}


def test_no_items_is_just_the_header(client: TestClient, db: Session) -> None:
    _, headers = owner(client, db)
    r = client.get(URL, headers=headers)
    assert r.status_code == 200, r.text
    assert [x for x in rows(r.text) if x] == [
        ["id", "title", "description", "created_at"]
    ]


def test_needs_a_login(client: TestClient) -> None:
    assert client.get(URL).status_code in (401, 403)
