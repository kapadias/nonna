// Contract test skeleton — TypeScript (vitest).
//
// A contract test pins the BOUNDARY: the request shape, the response shape, the enumerated errors,
// and the safety guarantees (validate-at-edge, reject-don't-clamp, idempotent retry). It is the
// deterministic gate that proves the implementation still honors the published contract — write it
// AGAINST the contract, then implement behind it (the implementation is replaceable; the contract is
// not). Pair this with the schema in ./openapi-contract.stub.yaml.
//
// Run:  npm test              (your test script, which runs vitest, pinned in your lockfile)
//
// Adopt: replace `createOrder` below with a call to your real handler or an HTTP client hitting the
// endpoint (e.g. supertest / fetch against a test server). Keep the assertions — they ARE the contract.

import { describe, it, expect, beforeEach } from "vitest";

// --- Contract types (mirror ./openapi-contract.stub.yaml) -------------------------------------
type Money = { currency: string; minor_units: number };
type Order = {
  id: string;
  sku: string;
  quantity: number;
  amount: Money;
  status: "pending" | "confirmed" | "cancelled";
};
type ErrorCode =
  | "invalid_input"
  | "unknown_sku"
  | "duplicate"
  | "rate_limited"
  | "internal";
type ApiError = { code: ErrorCode; message: string };
type Result<T> =
  | { ok: true; status: number; body: T }
  | { ok: false; status: number; body: ApiError };

// --- Reference implementation under test (REPLACE with your real handler / HTTP client) -------
// This stand-in makes the skeleton runnable and demonstrates the exact behavior the contract demands.
const KNOWN_SKUS = new Set(["SKU-1", "SKU-2"]);

function makeServer() {
  const seenKeys = new Map<string, Order>(); // idempotency store: key -> original result
  let seq = 0;

  function createOrder(
    idempotencyKey: string,
    raw: { sku?: unknown; quantity?: unknown; [k: string]: unknown },
  ): Result<Order> {
    // Idempotent replay: same key returns the original effect, exactly once.
    const prior = seenKeys.get(idempotencyKey);
    if (prior) return { ok: true, status: 201, body: prior };

    // Validate at the edge — reject out-of-contract input, never clamp-and-proceed.
    if (
      typeof raw.sku !== "string" ||
      raw.sku.length < 1 ||
      raw.sku.length > 64
    ) {
      return {
        ok: false,
        status: 400,
        body: { code: "invalid_input", message: "sku invalid" },
      };
    }
    if (
      typeof raw.quantity !== "number" ||
      !Number.isInteger(raw.quantity) ||
      raw.quantity < 1 ||
      raw.quantity > 10_000
    ) {
      return {
        ok: false,
        status: 400,
        body: { code: "invalid_input", message: "quantity out of range" },
      };
    }
    // Reject unknown fields rather than silently ignoring them.
    const allowed = new Set(["sku", "quantity"]);
    if (Object.keys(raw).some((k) => !allowed.has(k))) {
      return {
        ok: false,
        status: 400,
        body: { code: "invalid_input", message: "unknown field" },
      };
    }
    if (!KNOWN_SKUS.has(raw.sku)) {
      return {
        ok: false,
        status: 422,
        body: { code: "unknown_sku", message: "no such sku" },
      };
    }

    const order: Order = {
      id: `ord_${++seq}`,
      sku: raw.sku,
      quantity: raw.quantity,
      amount: { currency: "USD", minor_units: raw.quantity * 500 },
      status: "pending",
    };
    seenKeys.set(idempotencyKey, order);
    return { ok: true, status: 201, body: order };
  }

  return { createOrder };
}

// --- The contract -----------------------------------------------------------------------------
describe("POST /orders — contract", () => {
  let server: ReturnType<typeof makeServer>;
  beforeEach(() => {
    server = makeServer();
  });

  it("valid request returns a 201 with a well-typed Order", () => {
    const res = server.createOrder("key-aaaaaaaa", {
      sku: "SKU-1",
      quantity: 3,
    });
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.status).toBe(201);
    const o = res.body;
    expect(typeof o.id).toBe("string");
    expect(o.sku).toBe("SKU-1");
    expect(o.quantity).toBe(3);
    expect(o.amount).toMatchObject({ currency: "USD" });
    expect(Number.isInteger(o.amount.minor_units)).toBe(true); // money is integer minor units
    expect(["pending", "confirmed", "cancelled"]).toContain(o.status); // closed enum
  });

  it("rejects out-of-range input — does NOT clamp it", () => {
    const res = server.createOrder("key-bbbbbbbb", {
      sku: "SKU-1",
      quantity: 0,
    });
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("invalid_input"); // enumerated, typed error
  });

  it("rejects unknown fields at the edge", () => {
    const res = server.createOrder("key-cccccccc", {
      sku: "SKU-1",
      quantity: 1,
      admin: true,
    });
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.status).toBe(400);
  });

  it("returns a typed 422 for a well-formed but unknown SKU", () => {
    const res = server.createOrder("key-dddddddd", {
      sku: "SKU-NOPE",
      quantity: 1,
    });
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.status).toBe(422);
    expect(res.body.code).toBe("unknown_sku");
  });

  it("is idempotent: same key + same body => exactly one effect", () => {
    const first = server.createOrder("key-eeeeeeee", {
      sku: "SKU-2",
      quantity: 2,
    });
    const replay = server.createOrder("key-eeeeeeee", {
      sku: "SKU-2",
      quantity: 2,
    });
    expect(first.ok && replay.ok).toBe(true);
    if (!first.ok || !replay.ok) return;
    expect(replay.body.id).toBe(first.body.id); // same order, not a second one
  });
});
