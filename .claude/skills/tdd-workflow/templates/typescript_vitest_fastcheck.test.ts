// Golden + property test skeleton — TypeScript (vitest + fast-check).
//
// Copy into your suite and replace the placeholder SUT functions with imports of your own code.
//   • Golden   — assert an exact, hand-verified oracle. Catches *wrong*.
//   • Property — assert an invariant over generated inputs. Catches *the case you didn't think of*.
//
// Run:  npm test                  (your test script, which runs vitest)
// Deps: vitest, fast-check        (dev dependencies, pinned in your lockfile)
//
// Determinism: pass a fixed `seed` to fc.assert so a failing run reproduces exactly; if the SUT uses
// randomness or the clock, inject them (see .claude/rules/engineering.md).

import { describe, it, expect } from "vitest";
import fc from "fast-check";

// --- SUT placeholders -------------------------------------------------------------------------
// Replace with imports of the real functions under test, e.g.:
//   import { compound } from "../src/money";
//   import { encode, decode } from "../src/codec";
function compound(principal: number, rate: number, years: number): number {
  return principal * Math.pow(1 + rate, years);
}
function encode(x: number): string {
  return String(x);
}
function decode(s: string): number {
  return Number(s);
}

// --- Golden test: exact, hand-verifiable oracle -----------------------------------------------
describe("compound interest", () => {
  it("matches the hand-computed oracle", () => {
    // Oracle computed INDEPENDENTLY: 1000 * 1.05**3 = 1157.625. State where the number came from.
    // Use a tolerance for floats — never assert raw equality.
    expect(compound(1000, 0.05, 3)).toBeCloseTo(1157.625, 3);
  });
});

// --- Property test: round-trip invariant ------------------------------------------------------
describe("codec", () => {
  it("decode(encode(x)) === x for any safe integer", () => {
    fc.assert(
      fc.property(fc.integer(), (x) => {
        expect(decode(encode(x))).toBe(x);
      }),
      { seed: 0 }, // pin the seed so a failing example reproduces deterministically
    );
  });
});

// --- Property test: bounds / conservation -----------------------------------------------------
describe("chunkBySize", () => {
  // Replace with your real partitioner. Two invariants at once:
  //   1. no chunk's sum exceeds the cap (bounds)   2. nothing lost or duplicated (conservation)
  function chunkBySize(xs: number[], cap: number): number[][] {
    const out: number[][] = [];
    let cur: number[] = [];
    let running = 0;
    for (const x of xs) {
      if (cur.length > 0 && running + x > cap) {
        out.push(cur);
        cur = [];
        running = 0;
      }
      cur.push(x);
      running += x;
    }
    if (cur.length > 0) out.push(cur);
    return out;
  }

  it("never exceeds the cap and conserves every element", () => {
    fc.assert(
      fc.property(
        fc.array(fc.integer({ min: 0, max: 10_000 })),
        fc.integer({ min: 1, max: 512 }),
        (items, cap) => {
          const chunks = chunkBySize(items, cap);
          for (const chunk of chunks) {
            const sum = chunk.reduce((a, b) => a + b, 0);
            // a lone oversized item is allowed to be its own chunk
            expect(sum <= cap || chunk.length === 1).toBe(true);
          }
          expect(chunks.flat()).toEqual(items); // order + membership preserved
        },
      ),
      { seed: 0 },
    );
  });
});
