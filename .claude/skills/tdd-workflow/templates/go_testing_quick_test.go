// Golden + property test skeleton — Go (testing + testing/quick).
//
// Copy into your package's _test.go and replace the placeholder SUT functions with your own code.
//   • Golden   — assert an exact, hand-verified oracle. Catches *wrong*.
//   • Property — assert an invariant over generated inputs. Catches *the case you didn't think of*.
//
// Run:  go test ./...
// Deps: none — testing/quick is in the standard library. For richer generators and automatic
// shrinking, prefer pgregory.net/rapid (a dependency for your go.mod); the invariants below port
// directly. testing/quick is used here so the skeleton runs with zero external dependencies.
//
// Determinism: testing/quick seeds from its own source; if the SUT uses randomness or the clock,
// inject them so the test is reproducible (see .claude/rules/engineering.md).

package tdd

import (
	"math"
	"testing"
	"testing/quick"
)

// --- SUT placeholders -------------------------------------------------------------------------
// Replace these with the real functions under test in your package.

func compound(principal, rate float64, years int) float64 {
	return principal * math.Pow(1+rate, float64(years))
}

func encode(x int) string {
	if x == 0 {
		return "0"
	}
	neg := x < 0
	n := x
	if neg {
		n = -n
	}
	var buf []byte
	for n > 0 {
		buf = append([]byte{byte('0' + n%10)}, buf...)
		n /= 10
	}
	if neg {
		buf = append([]byte{'-'}, buf...)
	}
	return string(buf)
}

func decode(s string) int {
	neg := false
	i := 0
	if len(s) > 0 && s[0] == '-' {
		neg = true
		i = 1
	}
	n := 0
	for ; i < len(s); i++ {
		n = n*10 + int(s[i]-'0')
	}
	if neg {
		return -n
	}
	return n
}

// --- Golden test: exact, hand-verifiable oracle -----------------------------------------------
func TestCompoundInterestGolden(t *testing.T) {
	// Oracle computed INDEPENDENTLY: 1000 * 1.05**3 = 1157.625. State where the number came from.
	// Compare floats with an explicit tolerance — never ==.
	const want, tol = 1157.625, 1e-3
	got := compound(1000, 0.05, 3)
	if math.Abs(got-want) > tol {
		t.Fatalf("compound(1000, 0.05, 3) = %.6f; want %.6f ± %g", got, want, tol)
	}
}

// --- Property test: round-trip invariant ------------------------------------------------------
func TestEncodeDecodeRoundtrip(t *testing.T) {
	// For ANY int, decode(encode(x)) == x. quick.Check generates the inputs and shrinks failures.
	roundtrips := func(x int) bool {
		return decode(encode(x)) == x
	}
	if err := quick.Check(roundtrips, &quick.Config{MaxCount: 1000}); err != nil {
		t.Fatalf("round-trip property failed: %v", err)
	}
}

// --- Property test: bounds / conservation -----------------------------------------------------
func TestChunkBySizeBoundsAndConservation(t *testing.T) {
	// Replace chunkBySize with your real partitioner. Two invariants at once:
	//   1. no chunk's sum exceeds the cap (bounds)   2. nothing lost or duplicated (conservation)
	chunkBySize := func(xs []int, cap int) [][]int {
		var out [][]int
		var cur []int
		running := 0
		for _, x := range xs {
			if len(cur) > 0 && running+x > cap {
				out = append(out, cur)
				cur, running = nil, 0
			}
			cur = append(cur, x)
			running += x
		}
		if len(cur) > 0 {
			out = append(out, cur)
		}
		return out
	}

	prop := func(items []uint16, capSeed uint16) bool {
		cap := int(capSeed%512) + 1 // keep cap in [1, 512]
		xs := make([]int, len(items))
		for i, v := range items {
			xs[i] = int(v) % 10001 // keep values in [0, 10000]
		}
		chunks := chunkBySize(xs, cap)

		// bounds: each chunk's sum <= cap, unless it is a single oversized element
		for _, chunk := range chunks {
			sum := 0
			for _, v := range chunk {
				sum += v
			}
			if sum > cap && len(chunk) != 1 {
				return false
			}
		}
		// conservation: flatten equals the input, in order
		var flat []int
		for _, chunk := range chunks {
			flat = append(flat, chunk...)
		}
		if len(flat) != len(xs) {
			return false
		}
		for i := range xs {
			if flat[i] != xs[i] {
				return false
			}
		}
		return true
	}

	if err := quick.Check(prop, &quick.Config{MaxCount: 1000}); err != nil {
		t.Fatalf("bounds/conservation property failed: %v", err)
	}
}
