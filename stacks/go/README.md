# Nonna Stack Pack — Go

Toolchain: **gofmt + golangci-lint** (format + lint) · **go vet** (static analysis) · **go test -race -cover** (tests + coverage) · **testing/quick** or **pgregory.net/rapid** (property tests).

---

## Formatter — gofmt

```bash
gofmt -w "$FILE"
```

`gofmt` ships with the Go toolchain; no separate install needed. For import sorting, add `goimports` as well:

```bash
goimports -w "$FILE"
```

Install goimports:

```bash
go install golang.org/x/tools/cmd/goimports@latest
```

---

## Gate commands

### 1. Lint

```bash
golangci-lint run ./...
```

Install:

```bash
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
```

Configure enabled linters in `.golangci.yml`. A minimal recommended set: `errcheck`, `gosimple`, `govet`, `ineffassign`, `staticcheck`, `unused`. golangci-lint exits non-zero on any finding.

### 2. Static analysis

```bash
go vet ./...
```

`go vet` catches common mistakes the compiler misses (printf mismatches, unreachable code, etc.). Run it before tests; it is fast and built-in.

### 3. Tests + coverage

```bash
go test -race -coverprofile=coverage.out -covermode=atomic ./...
go tool cover -func=coverage.out
```

Then enforce a coverage floor with a shell check:

```bash
# Fail if total coverage is below 80%
COVERAGE=$(go tool cover -func=coverage.out | grep "^total:" | awk '{print $3}' | tr -d '%')
echo "Total coverage: ${COVERAGE}%"
awk -v cov="$COVERAGE" 'BEGIN { if (cov+0 < 80) { print "Coverage below 80% floor"; exit 1 } }'
```

- `-race` enables the data-race detector; never skip it in CI.
- `-covermode=atomic` is required when `-race` is also set.
- Raise the floor to 90 % for packages in `auth/`, `billing/`, or any persistence layer.

**CI enforcement:** the shell check exits non-zero when the floor is not met, failing the build.

A helper script `scripts/check-coverage.sh` is a common pattern — commit it so CI and local runs use the same check.

---

## Property tests — testing/quick or pgregory.net/rapid

**stdlib (testing/quick):** no extra dependency; ships with Go. Use `quick.Check` for simple invariants.

```go
import "testing/quick"
```

**pgregory.net/rapid** (recommended for more control):

```bash
go get pgregory.net/rapid
```

`rapid` supports custom generators, shrinking, and explicit seed control — use it for survival-critical surfaces where counterexample minimization matters.

**Template:** `.claude/skills/tdd-workflow/templates/go_testing_quick_test.go`

---

## Wire `/test`

Copy this block into your `/test` gate (commands run in order; first non-zero exit stops the gate):

```
go vet ./...
golangci-lint run ./...
go test -race -coverprofile=coverage.out -covermode=atomic ./...
go tool cover -func=coverage.out
awk -v cov="$(go tool cover -func=coverage.out | grep '^total:' | awk '{print $3}' | tr -d '%')" 'BEGIN { if (cov+0 < 80) { print "Coverage below 80% floor"; exit 1 } }'
```

---

## Pre-approved commands

`settings.local.json` lets `go test`, `go vet`, `gofmt`, `goimports` and `golangci-lint` run without a prompt. The other `go` commands (`go run`, `go install`, `go get`, `go tool cover`) and `awk` are not on the list, because they run any code or install anything, so the coverage-floor check above (`go tool cover` and `awk`) asks first, and so do the install commands below.

---

## Install all dev dependencies

```bash
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install golang.org/x/tools/cmd/goimports@latest
go get pgregory.net/rapid   # if using rapid for property tests
```
