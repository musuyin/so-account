# Project review and coding plan

Review date: 2026-10-27. Source baseline: `5876c3039503ae7b03d36c7c1b7f95249331f2ae`, application `1.2.0+17`, database schema 9.

Subsequent implementation and v1.3.0 release validation are tracked in [validation-v1.3.0.md](validation-v1.3.0.md). The review below retains its original planning-time scope and evidence; release work was separately authorized after this review.

This is a planning-only review. No application, test, build, or configuration changes were made. The pre-existing `.gitignore` modification is outside this review. Implementation below is proposed, not completed.

## Review scope and evidence

Inspected the project instructions, README, architecture/data/delivery documentation, shared providers, database migration structure, ledger write paths, entry composer, import parser and workflow, CSV exports, backup codec/service/page, media lifecycle, update transport/download paths, mobile CI, and representative repository/widget/integration tests. This is a targeted source review, not an exhaustive audit of every file or native platform implementation.

No tests, builds, benchmarks, network release checks, or device runs were performed in this review. Existing test counts and release results in the README are historical claims, not fresh verification. No screenshots were generated or visually accepted in this review; rendering inspection is an implementation acceptance requirement below.

The existing architecture is worth retaining: feature-oriented modules, integer minor-unit money, explicit currency isolation, shared SQLite transactions for combined writes, isolated backup validation, immutable restored photos published before database commit, CSV formula neutralization, and update origin/size/hash checks. Import parsing already runs in an isolate and XLSX expansion already has a size cap; neither should be proposed as a missing feature.

## Prioritized findings

Priority describes proposed implementation order. “Confirmed” means directly visible in source; impact scenarios have not been executed unless explicitly stated.

| ID | Priority | Finding | Evidence and confidence |
| --- | --- | --- | --- |
| R1 | P1 | Successful backup export does not guarantee that the same backup meets restore limits. | Confirmed limit mismatch: `lib/features/backup/domain/backup_codec.dart:14` checks payload size before adding `manifest.json`, while decoder totals include the manifest at lines 70 and 89–92. `lib/features/backup/data/backup_service.dart:303` rejects more than 100,000 rows per collection on restore, but export at line 31 has no equivalent row check. A compressible payload close to 100 MB, or a small-record collection above 100,000 rows, can pass export and fail restore. |
| R2 | P1 | Device recovery and upgrade acceptance is much narrower than the implemented feature set. | Confirmed coverage boundary: `integration_test/persistence_test.dart:10` checks a database close/reopen within one test process. `.github/workflows/mobile.yml` runs unit/widget checks and platform builds, but no device integration job. This does not exercise process death, system file providers, or signed APK replacement. No runtime defect is asserted. |
| R3 | P2 | Unrelated writes trigger whole-ledger reloads and broad UI work. | Confirmed architecture: `lib/app/providers/providers.dart:37–68` watches ten tables and reloads all ten in one transaction. Home and account-detail pages filter data in memory. Performance impact is a profiling hypothesis, not a measured regression. |
| R4 | P2 | Complex form and import orchestration is concentrated in large widgets. | `lib/features/ledger/presentation/entry_form.dart` owns draft state, selection, dialogs, and saving. `lib/features/importing/presentation/import_page.dart` owns file selection, mapping, preview, category creation, and commit coordination. This increases change coupling; file size alone is not a correctness defect. |
| R5 | P2 | Visual evidence exists, but CI does not retain it as an explicit review artifact. | Tests including `test/exposed_accounts_ui_test.dart` and `test/entry_purchase_flow_test.dart` write `.tooling/screenshots`; mobile CI uploads build logs/APK, not those screenshots. Existing privacy semantics coverage should be extended, not replaced. |
| R6 | P3 | Engineering documents contain contradictory current-state descriptions. | `docs/engineering/roadmap.md:40` still says schema 7 although the same file mentions schema 9 and `AppDatabase.schemaVersion` is 9. `docs/engineering/architecture.md` omits several implemented feature directories from its tree and describes purchase writes as concentrated in InventoryRepository, although LedgerRepository now orchestrates expense-plus-item creation. |

## Implementation sequence

### Step 1 — Make backup limits symmetric (R1)

**Targets:** `lib/features/backup/domain/backup_codec.dart`, `lib/features/backup/data/backup_service.dart`, `test/features/backup_test.dart`, `docs/engineering/backup-format.md`.

1. Add regression cases first for payload-plus-manifest accounting and collection row limits. Demonstrate export/restore disagreement with synthetic data; avoid committing a huge binary fixture.
2. Define shared row/file/expanded-size limits used on both sides. Compute manifest UTF-8 bytes once and include them in the encoder's expanded-byte budget. Keep the compressed-size check and decoder's pre-decompression checks.
3. Check collection counts before expensive JSON/photo assembly. For the first fix, keep the existing restore limit and reject an oversized export with an actionable message before delivering a file. Never silently truncate records.
4. Preserve schema 1–9 compatibility and the current atomic restore/media publication order. This is a validation change, not a database migration or new backup format.
5. Document that whole-ledger backup beyond the current supported limit needs a separate capacity design; splitting files manually is not an equivalent full backup.

**Acceptance:** just-below/at/above boundary tests agree between encode and decode; valid current-schema exports restore into a fresh database with matching IDs, balances, debt links, item links, goal contributions, and preferences; rejection and injected failure leave the existing database/photos intact. Retain malformed archive and legacy backup tests. Use small injectable test limits or a bounded boundary test to keep routine CI memory use reasonable.

### Step 2 — Add reproducible device recovery coverage (R2)

**Targets:** `integration_test/`, a host-side driver under `tool/`, `.github/workflows/mobile.yml`, `docs/engineering/roadmap.md`.

1. Build an isolated synthetic ledger fixture covering multiple currencies, transfer, loan/settlement, archived accounts, adjustment, item/photo, and goal contributions. Never use or clear a personal ledger.
2. Keep the existing close/reopen test, then add a host-driven seed → terminate process → relaunch → verify scenario. A Dart database reopen must not stand in for process-death coverage.
3. Add restore failure/relaunch checks around staged media and database commit, verifying that committed rows always reference available photos and that failed restore retains old data.
4. Add an emulator integration job, initially dispatchable to establish reliability. Publish test output and device metadata; promote stable deterministic cases into regular CI.
5. Write a separate physical-device procedure for Android document-provider save/open, share cancellation, camera/gallery permission denial and lost selection, low storage, and previous signed version → candidate version installation. Verify balances and relationships after upgrade and relaunch.

**Acceptance:** each scenario records app/build, OS/API, device, fixture, expected totals, actual result, and evidence. Emulator, physical Android, iOS simulator, and physical iPhone results remain separate. A device-dependent step remains pending until that device is available; builds do not satisfy it. Use protected release signing only through the existing release workflow, never commit credentials.

### Step 3 — Profile and bound ledger reads (R3)

**Targets:** `lib/app/providers/providers.dart`, ledger query methods, `home_page.dart`, `account_detail_page.dart`, and selected inventory/goals consumers.

1. Add a deterministic local benchmark fixture at 1,000, 10,000, and 100,000 entries, with representative accounts and links. Measure profile-mode startup, month switching, account details, import completion, frame timing, query counts, and peak memory on a named Android target.
2. First migrate home and account detail to scoped queries: currency/date/account filters in SQL, deterministic ordering, and bounded pages for long lists. Keep small reference data such as categories separate from the full transaction history.
3. Use `(date, createdAt, id)` or an equivalent unique ordering for pagination. Keep SQL aggregates over the entire requested range, not just the displayed page. Preserve calendar daily totals independently of list pagination.
4. Add indexes only after inspecting query plans and measurements. If indexes require a migration, include the next schema snapshot and upgrade tests in the same change.
5. Retain coherent multi-table reads for restore and any view that combines related records. Do not replace one atomic snapshot with independently timed streams that can mix pre-restore and post-restore data.

**Acceptance:** scoped results match the current implementation on synthetic datasets, including equal dates/timestamps, archived history, currency isolation, filters, and edits/deletes between page loads. Record before/after numbers. Proposed initial budget: visible month/detail load p95 below 300 ms at 10,000 rows on the chosen target; confirm or revise the budget from baseline measurements before committing to it. No performance claim without device measurements.

### Step 4 — Extract form/workflow state incrementally (R4)

**Targets:** entry composer and import page, new feature-local draft/controller files, existing entry/import flow tests.

1. Extract an entry draft model with explicit transitions for expense, income, transfer, borrowing/lending, and repayment/collection. Preserve payer/payee exchange and original-loan IDs.
2. Extract save orchestration while keeping money and relationship validation in repositories and expense-plus-item creation in the existing shared transaction.
3. Extract the import workflow into explicit select/map/preview/commit states. Preserve background parsing, current row limits, income/expense-only scope, ignored zero/blank-account rows, and intentional duplicate retention.
4. Keep each extraction behavior-preserving and independently reviewable. Do entry state and import state in separate changes; do not combine this work with schema changes or a visual redesign.

**Acceptance:** existing flow tests continue to pass; add focused transition tests for “再记” clearing only intended fields, cancelled item dialogs retaining the previous draft, failed saves retaining inputs, stale/archived account selections, and import cancellation/retry. Add tests only where existing coverage does not already prove the behavior. No generic interface layer or application-wide state-management rewrite is needed.

### Step 5 — Preserve visual and accessibility evidence (R5)

**Targets:** existing screenshot-producing widget tests, mobile CI artifact upload, a short UI acceptance checklist under `docs/`.

1. Upload existing generated screenshots and relevant test logs from CI, including failed runs when files are available. Use synthetic amounts/accounts only.
2. Cover direct selection, selection restrictions, cancel/save, date filtering, hidden amounts including semantics, and the separate today/selected-date/heatmap indicators. Retain existing privacy tests.
3. Capture the configured palettes in light/dark mode at 320 and 390 logical pixels and enlarged text. Include keyboard-open composer, item dialog, assets, and six-week calendar states.
4. Inspect actual rendered images and record acceptance. Introduce a small stable golden set only where it adds useful regression detection; do not automatically baseline every screenshot or accept changed goldens without inspection.

**Acceptance:** common choices stay visible and directly selectable; selected values retain a clear change action; no overflow, forced text shrinking, inaccessible amounts, or unreadable heatmap labels. Screenshot review and device interaction checks are recorded separately from automated results. Existing intentionally chosen currency controls should not be changed merely for consistency during this work.

### Step 6 — Reconcile documentation (R6)

**Targets:** `docs/engineering/roadmap.md`, `docs/engineering/architecture.md`, relevant backup/update documentation.

Correct the roadmap's current schema statement, expand the feature directory overview, and describe the actual purchase transaction owner and repository collaboration. Retain dated historical results as dated results rather than rewriting old test counts as current. Track local checks, CI checks, published artifact checks, and device acceptance in separate fields linked to evidence.

**Acceptance:** schema references agree with source; architecture reflects implemented flows; each validation claim has a date/source and does not imply unperformed device acceptance. This documentation cleanup can be done independently of the code changes.

## Delivery and validation gates

Recommended order: Step 1 → Step 2 → Step 3 → Step 4 → Step 5, with Step 6 independent. Step 5 can accompany any UI-facing work. Keep fixes, device infrastructure, query optimization, and state extraction in separate changes so each can be reviewed and reverted independently.

For implementation, use the pinned project-local Flutter SDK and cached dependencies where available. Run focused tests for each changed behavior, then static analysis and the complete Flutter suite before integration. Run Python tooling tests when changing host/CI tooling. Require generated database consistency and migration tests only when database definitions or generated code change. Complete the existing platform CI for relevant platform changes.

Do not broaden this plan into cloud sync, OCR, exchange rates, live investment pricing, transfer/debt imports, a new database engine, or a release. Those require separate product scope. Encrypted backups are also a separate format/key-management decision, not a prerequisite for fixing R1.

Completion of this document means the review and plan are delivered. It does not mean any proposed fix, benchmark, migration, screenshot review, installation, or release has happened.
