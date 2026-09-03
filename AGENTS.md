# Repository Agent Guide

This file is the single source of truth for assistants working in this repository. Read it before changing or generating project files. Keep tool-specific rules short and link back here instead of copying these instructions.

## Product and stack

- Product name: **Ferretería y Construcciones El Conejo C.A.**
- Backend: Python 3.10+, Flask application factory (`create_app`), Flask-Login, Flask-WTF, SQLAlchemy, PyMySQL, and MySQL 8.
- Frontend: server-rendered Jinja2, Tabler (which already includes Bootstrap), native JavaScript, CSS, and Chart.js. Do not introduce a SPA framework or a second Bootstrap distribution.
- Text presented to users is Spanish and encoded as UTF-8.

## Architecture boundaries

Follow the existing flow:

```text
Flask route -> controller -> service -> SQLAlchemy model -> MySQL
```

- Routes define HTTP contracts and delegate request handling.
- Controllers parse requests and prepare responses or templates.
- Services own business rules, authorization-sensitive operations, and transactions.
- Models define persistence. Do not move business logic into JavaScript or Jinja templates.
- Some page routes render templates directly and some existing dashboard queries are route-level. Reuse the current architecture; do not rewrite unrelated code just to make it uniform.

## Change rules

1. Apply KISS: prefer the smallest solution that fully satisfies the approved requirement.
2. Apply YAGNI: do not add speculative endpoints, screens, modules, layers, components, dependencies, or configuration.
3. Do not invent routes or expose menu links unless the route exists and the current user is authorized to use it.
4. Preserve existing routes, status codes, API payloads, form field names, validation, authentication, role/permission checks, and JavaScript behavior.
5. Before changing markup, trace every affected DOM ID, name, `data-*` attribute, selector, and event handler. Treat them as contracts unless the corresponding JavaScript is updated and verified in the same work unit.
6. Preserve inventory invariants: stock changes go through the existing services, create stock movements, enforce availability, and retain the current transaction and locking behavior.
7. Do not hardcode mockup metrics, inventory, sales, names, dates, forecasts, or statuses. Visible data must come from the backend or a truthful application state.
8. Never add `try`/`catch` or `try`/`except` around imports.

## Visual source and accessibility

- Use `references/` as the approved visual direction and read `references/README.md` plus `references/MANIFEST.csv` before implementing a referenced screen.
- **Never read, copy, package, or use anything in `references/90_archivo_no_usar/`.**
- The official logo source is `references/00_marca/logo_oficial_el_conejo.png`. Preserve that source; copy it into `app/static/` only when the browser needs a static asset.
- Use a light application background and sidebar, white cards, rounded surfaces, subtle borders/shadows, consistent spacing, and clear hierarchy. Use blue for navigation and primary actions, green for positive/available states, orange for warnings, and red for critical/destructive states.
- Keep layouts, tables, forms, modals, and navigation usable on desktop, tablet, mobile, and browser zoom.
- Keyboard navigation must work. Provide visible focus, semantic landmarks, labels for form controls, accessible names for icon-only controls, meaningful table headers, and `aria-current` for active navigation where applicable.
- Provide coherent loading, empty, insufficient-data, error, and success states. Do not present predictions when the backend reports that a model or sufficient data is unavailable.

## Authorization and privacy

- Backend permission checks are authoritative. UI visibility complements them; it never replaces them. Preserve restrictions for `admin`, `inventario`, `vendedor`, and granular permissions.
- Do not read, print, package, upload, or commit `.env`, untracked environment overrides, `instance/`, `uploads/`, `private_imports/`, user files, credentials, tokens, database dumps, or generated reports containing private data. A versioned `.env.example` may be read only as a configuration schema and must never contain real secrets.
- Treat `.codegraph/`, `repomix-output.*`, logs, test artifacts, and generated analysis as local/sensitive until reviewed. Keep secrets and private paths out of prompts, screenshots, diffs, issues, and pull requests.
- Do not expose internal exceptions, configuration values, historical imports, or user data in UI or API changes.

## Verification by risk

Start with the smallest relevant checks. Never report a check as passed unless it ran successfully.

### Safe, non-data-mutating checks

```powershell
git status --short --branch
git diff --check
npm run codegraph:doctor
npm run openspec:doctor
```

Use `node --check` on each changed JavaScript file. Review the full diff and confirm no secret, private file, generated output, or unrelated change was included.

### Isolated disposable SQLite suites

These suites create their own temporary SQLite data:

```powershell
python scripts/test_delivery_note_pdf.py
python scripts/test_historical_imports.py
python scripts/test_prediction_readiness.py
```

### Requires an explicitly disposable database or environment

- Treat every other script under `scripts/` as stateful until its source is inspected. This includes initialization, migrations, cleanup scripts, live-server HTTP suites, and PowerShell suites.
- Do not run `scripts/init_db.py`, `scripts/migrate_*.py`, `scripts/cleanup_*.py`, or live HTTP tests against valuable data.
- Before a stateful check, verify the target database, seed users, server, file storage, and cleanup behavior. Record the exact command and result.

## Tools and specifications

- `AGENTS.md` owns repository-wide assistant instructions. Cursor rules and tool configuration must point here rather than duplicate it.
- OpenSpec stores approved requirements, scenarios, design decisions, and acceptance criteria. It does not duplicate this guide or grant implementation approval.
- Use the existing package scripts for CodeGraph, Repomix, and OpenSpec. `npm run repomix:pack` writes `repomix-output.xml`; inspect exclusions and sensitive content before running or sharing it.
- Archify diagrams must reflect repository evidence and exclude private/generated data.
- Inspect Gentle AI version, help, compatibility, dry-run output, and generated paths before any installation command. Never run `gentle-ai install` blindly.
- Ponytail reinforces KISS/YAGNI and does not require repository scaffolding. Do not add a tool when an installed or native capability already covers the need.
- RTK is undefined for this project. Do not assume Redux Toolkit or configure RTK until the user identifies the exact tool.

### zg Phase 2B security exception

**Decision: ADOPT WITH DOCUMENTED SECURITY EXCEPTION.** The approved evaluation rated utility **3/5** and privacy **PASS**. This exception is limited to `@zvec/zvec-grep@0.2.1`, the model `local/potion-code-16m-v2`, and text/code content through `npm run zg:index`.

- Finding: `zg -> @huggingface/transformers@3.8.1 -> sharp@0.34.5` reaches `GHSA-f88m-g3jw-g9cj` (upstream severity: **High**; patched upstream in `sharp >=0.35.0`). The three High audit package entries derive from this single root GHSA.
- Approved reachability: **NOT LOADED**. The allowed Potion Model2Vec text/code path does not load the Transformers.js image backend.
- Image extraction, image processing, and multimodal indexing are prohibited. In `@zvec/zvec-grep@0.2.1`, only GIF, JPEG/JPG, PNG, and WebP can enter `ImageExtractor`; those raster formats are excluded by default unless explicitly selected. The approved command keeps the existing case-insensitive `--iglob` exclusions for those formats plus `.tif`/`.tiff`/`.vips` as defense in depth. SVG, AVIF, HEIC, and BMP are not ImageExtractor formats in 0.2.1 and do not reach the sharp/libvips image-processing path. `.repomixignore` remains the mandatory privacy boundary and is validated fail-closed (required exclusions present, no `!` re-inclusion) before either a missing-index pass or an existing-index check. Remote embeddings, multimodal operation, the Transformers.js backend, `--allow-remote`, API keys, any other model, and a `sharp` override are prohibited. Do not use `--hidden`, `--no-ignore`, or `zg install`; no supported upstream mitigation currently permits overriding to `sharp >=0.35.0`.
- MCP is not currently approved; do not configure or use zg MCP.
- A pre-existing `.zvec-grep/` index must pass `npm run zg:preflight` before use. Mismatch or unknown state blocks `npm run zg:index` and `npm run zg:status`. Rebuild, reset-paths, or drop require an explicit operator decision; never automatically repair an incompatible index.

Require a new security review before use if any of these occurs:

1. `@zvec/zvec-grep` changes from `0.2.1`.
2. `@huggingface/transformers` or `sharp` changes.
3. Another High or Critical GHSA appears.
4. The embedding model changes.
5. Image indexing or processing is enabled.
6. Remote embeddings or multimodal operation is enabled.
7. zg MCP configuration is attempted.
8. An upstream zg release supports `sharp >=0.35.0`.

## Git workflow

- Check Git status before work. Preserve pre-existing changes and never overwrite, stage, or commit someone else's work.
- Do not use `git reset --hard`, rewrite history, discard work, or perform destructive cleanup.
- Keep changes small and thematic. Separate agent/tooling configuration from frontend redesign; keep verification and documentation with the behavior they cover.
- Before a commit, show/review the diff and record every executed check with its exact result. Commit, push, and pull-request creation require the user's authorization and normal repository policy.

## Per-phase handoff

Before editing, report: objective, diagnosis, planned files, risks, and planned checks.

After editing, report: summary, files changed, KISS/YAGNI decisions, exact checks and results, screenshots taken, limitations, and—only when actually created—the commit hash and pull-request identifier/link.
