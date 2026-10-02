"""Golden + property test skeleton — Python (pytest + Hypothesis).

Copy into your test suite and replace the placeholder `solution under test` (SUT) functions with
imports of your own code. The two styles are complementary:

  • Golden  — assert an exact, hand-verified oracle. Catches *wrong*.
  • Property — assert an invariant over generated inputs. Catches *the case you didn't think of*.

Run:  pytest -q
Deps: pytest, hypothesis   (dev dependencies, pinned in your lockfile)

Determinism: Hypothesis seeds its own RNG; if your SUT uses randomness or the clock, inject a seed and
a fixed `now` so the test is reproducible bit-for-bit (see .claude/rules/engineering.md).
"""

from __future__ import annotations

from pytest import approx
from hypothesis import given
from hypothesis import strategies as st


# --- SUT placeholders -------------------------------------------------------------------------
# Replace these two with imports of the real functions under test, e.g.:
#   from mypkg.money import compound
#   from mypkg.codec import encode, decode
def compound(principal: float, rate: float, years: int) -> float:
    """Compound interest: A = P(1 + r)^n. Replace with the real implementation."""
    return principal * (1 + rate) ** years


def encode(x: int) -> str:
    return str(x)


def decode(s: str) -> int:
    return int(s)


# --- Golden test: exact, hand-verifiable oracle -----------------------------------------------
def test_compound_interest_golden() -> None:
    # Oracle computed INDEPENDENTLY: 1000 * 1.05**3 = 1157.625. State where the number came from.
    # Pin the exact value with an explicit tolerance — never assert raw float equality.
    assert compound(principal=1000, rate=0.05, years=3) == approx(1157.625, abs=1e-3)


# --- Property test: round-trip invariant ------------------------------------------------------
@given(st.integers())
def test_encode_decode_roundtrip(x: int) -> None:
    # For ANY valid input, decoding the encoding returns the original. Hypothesis hunts the
    # counterexample (0, negatives, huge ints) you would not have hand-picked.
    assert decode(encode(x)) == x


# --- Property test: bounds / conservation -----------------------------------------------------
@given(
    st.lists(st.integers(min_value=0, max_value=10_000)),
    st.integers(min_value=1, max_value=512),
)
def test_chunking_respects_cap_and_conserves(items: list[int], cap: int) -> None:
    # Replace `chunk_by_size` with your real partitioner. Two invariants at once:
    #   1. no chunk's sum exceeds the cap (bounds)   2. nothing is lost or duplicated (conservation)
    def chunk_by_size(xs: list[int], limit: int) -> list[list[int]]:
        out: list[list[int]] = []
        cur: list[int] = []
        running = 0
        for x in xs:
            if cur and running + x > limit:
                out.append(cur)
                cur, running = [], 0
            cur.append(x)
            running += x
        if cur:
            out.append(cur)
        return out

    chunks = chunk_by_size(items, cap)
    for chunk in chunks:
        assert (
            sum(chunk) <= cap or len(chunk) == 1
        )  # a lone oversized item is its own chunk
    assert [
        x for chunk in chunks for x in chunk
    ] == items  # order + membership preserved
