"""search: GET /api/v1/items/search?q=<text> (tasks/real/search/prompt.txt). Hidden from the agent."""

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.models import ItemCreate, UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string

URL = f"{settings.API_V1_STR}/items/search"


def owner(client: TestClient, db: Session):
    email, password = random_email(), random_lower_string()
    user = crud.create_user(
        session=db, user_create=UserCreate(email=email, password=password)
    )
    return user, user_authentication_headers(
        client=client, email=email, password=password
    )


def item(db: Session, user, title: str):
    return crud.create_item(
        session=db, item_in=ItemCreate(title=title), owner_id=user.id
    )


def test_matches_title_ignoring_case_within_own_items(
    client: TestClient, db: Session
) -> None:
    tag = random_lower_string()[:10]
    a, headers = owner(client, db)
    b, _ = owner(client, db)
    blue = item(db, a, f"{tag} Blue Widget")
    pro = item(db, a, f"{tag} widget pro")
    item(db, a, f"{tag} Red gadget")
    item(db, b, f"{tag} WIDGET of someone else")
    r = client.get(URL, params={"q": "wIdGeT"}, headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == 2
    assert [x["id"] for x in body["data"]] == [
        str(pro.id),
        str(blue.id),
    ]  # newest first
    assert {"id", "title", "owner_id"} <= set(body["data"][0])


def test_a_superuser_searches_every_item(
    client: TestClient, db: Session, superuser_token_headers: dict[str, str]
) -> None:
    tag = random_lower_string()[:10]
    a, _ = owner(client, db)
    b, _ = owner(client, db)
    ids = {
        str(item(db, a, f"x {tag} one").id),
        str(item(db, b, f"y {tag.upper()} two").id),
    }
    r = client.get(URL, params={"q": tag}, headers=superuser_token_headers)
    assert r.status_code == 200, r.text
    assert {x["id"] for x in r.json()["data"]} == ids
    assert r.json()["count"] == 2


def test_no_match_is_empty(client: TestClient, db: Session) -> None:
    a, headers = owner(client, db)
    item(db, a, "something")
    r = client.get(URL, params={"q": random_lower_string()}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"data": [], "count": 0}


def test_needs_a_login(client: TestClient) -> None:
    assert client.get(URL, params={"q": "x"}).status_code in (401, 403)
