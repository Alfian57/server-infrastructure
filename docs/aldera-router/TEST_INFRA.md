# E2E Test Infra: AI API Relay Platform

## Test Philosophy
- **Opaque-Box & Requirement-Driven**: Tests are designed directly from `ORIGINAL_REQUEST.md` and user-facing specifications without coupling to internal module structures.
- **Methodology**: Systematic 4-tier testing strategy combining Category-Partition, Boundary Value Analysis (BVA), Pairwise Combinatorial Testing, and Real-World Workload Testing.
- **Progressive Testability**: Verification uses standard protocols (HTTP, SSE, SQL queries, Telegram update simulation).

---

## Feature Inventory & Test Coverage Goals
| # | Feature | Requirement Source | Tier 1 (Features) | Tier 2 (Boundaries) | Tier 3 (Combinations) |
|---|---------|-------------------|:-----------------:|:-------------------:|:---------------------:|
| 1 | Healthcheck `/healthz` | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 2 | Model Discovery `/v1/models` | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 3 | Chat Completions `/v1/chat/completions` | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 4 | Messages API `/v1/messages` | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 5 | Virtual Key Auth (`sk-toko-...`) | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 6 | Pre-flight Balance Guard (402) | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 7 | Stream Options & Fallback Estimator | ORIGINAL_REQUEST §R1 | ≥5 cases | ≥5 cases | ✓ |
| 8 | Atomic Balance & Audit Ledger | ORIGINAL_REQUEST §R1, R3 | ≥5 cases | ≥5 cases | ✓ |
| 9 | Bot User Registration (`/start`) | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 10 | Bot Key Management (`/apikey`) | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 11 | Bot Balance & Pricing (`/saldo`, `/harga`) | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 12 | Topup Ticket & QRIS Flow (`/topup`) | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 13 | Admin Approval & Idempotency | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 14 | Admin Security & Controls (`/addsaldo`, etc.) | ORIGINAL_REQUEST §R2 | ≥5 cases | ≥5 cases | ✓ |
| 15 | Deployment & Compose Syntax | ORIGINAL_REQUEST §R4 | ≥5 cases | ≥5 cases | ✓ |

---

## Test Architecture
- **Test Runner**: Python pytest runner with `asyncio` and `httpx` (`tests/e2e/test_runner.py`).
- **Invocation**: `pytest -v tests/e2e` or `./verify-relay.sh`
- **Pass/Fail Semantics**: 100% of tests must pass with exit code 0.
- **Directory Layout**:
  - `tests/e2e/tier1_features/`: Happy-path equivalence tests isolating each feature.
  - `tests/e2e/tier2_boundaries/`: Negative tests, invalid API keys, zero/negative balances, concurrent race conditions (10 concurrent requests).
  - `tests/e2e/tier3_pairwise/`: Pairwise interactions (streaming + low balance, topup + immediate concurrent inference, model pricing changes + usage log calculation).
  - `tests/e2e/tier4_realworld/`: End-to-end user journeys (New user -> `/start` -> `/apikey` -> `/topup` -> Admin Approve -> `/saldo` -> Run Cursor completions -> Balance deduct -> Check ledger).
  - `tests/mock_upstream/`: Mock 9router HTTP & SSE server simulating streaming chunks and token usage.

---

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Full Customer Onboarding & Inference Journey | `/start`, `/apikey`, `/topup`, Admin Approve, `/v1/chat/completions` non-streaming, `/saldo`, ledger audit | High |
| 2 | High-Concurrency Stress & Overdraft Defense | 10 concurrent requests at exact boundary balance (Rp 1,000) ensuring zero negative balance and atomic ledger consistency | High |
| 3 | SSE Streaming Interruption & Token Recovery | Client disconnects mid-stream; verifies fallback estimator logs partial tokens and deducts balance | High |
| 4 | Double-Click Topup Attack Defense | Simultaneous double approve callback on the same topup ticket; verifies exactly 1 succeeds and balance credits only once | Medium |
| 5 | Unauthorized Intrusion & Permission Rejection | Non-admin user attempting `/addsaldo`, `/stats`, `/setprice`, and tampering with other user API keys | Medium |

---

## Coverage Thresholds
- **Tier 1 (Feature Coverage)**: ≥75 test cases (≥5 per feature).
- **Tier 2 (Boundary & Corner Cases)**: ≥75 test cases (boundary limits, 401/402 responses, 10 concurrent requests race condition).
- **Tier 3 (Cross-Feature Combinations)**: ≥15 test cases (pairwise matrix).
- **Tier 4 (Real-World Scenarios)**: ≥8 multi-step end-to-end integration workflows.
- **Total Minimum**: ≥173 test cases across the entire suite.
