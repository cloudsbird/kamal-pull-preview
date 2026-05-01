# Fix Plan for kamal-pull-preview

## Context

You are working on `kamal-pull-preview`, a Ruby gem that provides per-PR preview environments using Kamal 2.x. The codebase is at `/workspaces/kamal-pull-preview`. Tests are run with `bundle exec rake spec`. All 77 specs currently pass.

## Task

Fix the following issues. Make **minimal, focused changes** — do not refactor unrelated code. Ensure all tests still pass after each change.

---

## Issue 1: `db_seed` feature is documented but completely unimplemented

The README documents database seeding from S3, HTTPS, local files, and shell commands, but there is zero implementation code.

### What to implement

1. **Config support**: Add `db_seed` to `Config::FIELDS`, load it from YAML, and validate it.
   - `db_seed` is a Hash with keys: `source` (String), `format` (String, default `"auto"`), `required` (Boolean, default `false`), `table_check` (Boolean, default `true`).
   - If `db_seed` is present, `source` must be non-empty.
   - `format` must be one of: `"auto"`, `"custom"`, `"plain"`, `"directory"`.

2. **DumpFetcher class**: Create `lib/kamal_pull_preview/dump_fetcher.rb`.
   - `#initialize(source:, format: "auto")`
   - `#available?` — checks if source is reachable:
     - `s3://` — check with `aws s3 ls` or similar.
     - `https://` / `http://` — check with `curl -I` or `HEAD` request.
     - bare file path — `File.exist?`.
     - `cmd:` prefix — always returns `true`.
   - `#fetch` — returns an IO or path to the dump:
     - `s3://` — download to temp file via `aws s3 cp`.
     - `https://` — download to temp file via `curl -fsSL`.
     - bare file path — return the path directly.
     - `cmd:` — execute command and capture stdout to temp file.
   - `#detect_format` — inspect file magic bytes:
     - Starts with `PGDMP` → `"custom"`.
     - First line starts with `--` or `BEGIN` → `"plain"`.
     - Is a directory → `"directory"`.
     - Otherwise → `"auto"` (falls back to plain).

3. **DatabaseManager integration**:
   - Add `restore_seed(pr_number:, destination_type:)` method.
   - `destination_type` can be: `:shared_schema`, `:accessory_postgres`, `:sqlite`, `:none`.
   - Before restoring, check if target already has tables (when `table_check: true`):
     - Postgres: `SELECT count(*) FROM information_schema.tables WHERE table_schema = 'pr_N'`.
     - SQLite: check if volume file exists on the remote host.
   - If `table_check` is true and tables exist, skip restore and log a notice.
   - If source is unreachable and `required: true`, raise `DbError`.
   - If source is unreachable and `required: false`, log warning and continue.
   - Restore strategies:
     - `shared_schema` → `pg_restore` with `search_path = pr_N` or `psql` for plain.
     - `accessory_postgres` → SCP dump to host, then `docker exec` with `pg_restore`/`psql` inside container.
     - `sqlite` → SCP or `docker cp` the `.sqlite3` seed file to container volume.
     - `none` → log warning, skip.

4. **Deployer integration**:
   - In `Deployer#deploy`, after `boot_all` and before `kamal deploy`, call `DatabaseManager#setup_seed` if `db_seed` is configured.
   - Pass the detected destination type (based on `db_strategy` and accessories).

5. **Add specs**:
   - `spec/kamal_pull_preview/dump_fetcher_spec.rb` covering all source types, availability checks, and format detection.
   - Add `db_seed` config validation tests to `config_spec.rb`.
   - Add seed restore tests to `database_manager_spec.rb`.

---

## Issue 2: `idle_stop_minutes` is configured but never used

The config accepts `idle_stop_minutes` (default 240) but nothing stops idle containers.

### Fix

**Option A (recommended — document it):**
Add a comment in `templates/kamal-pull-preview.yml.erb` and the README explaining that `idle_stop_minutes` is reserved for future use and currently has no effect. This is the minimal change.

**Option B (if you want to implement it):**
Add a `stopped_at` column to the `previews` table, add a `stop` command to the CLI that runs `kamal stop -d pr-N`, and make `Cleaner` also clean up stopped previews after `idle_stop_minutes`.

**Use Option A** for now to avoid scope creep.

---

## Issue 3: CI workflow uses non-existent `actions/checkout@v5`

File: `.github/workflows/ci.yml` line 21.

### Fix

Change `actions/checkout@v5` to `actions/checkout@v4`.

---

## Issue 4: Missing `.gitignore` entry for `.ruby-lsp/`

### Fix

Add `.ruby-lsp/` to `.gitignore`.

---

## Issue 5: Resource leak on failed deploy

In `Deployer#deploy`, if `kamal deploy` fails after accessories have booted and DB has been created, nothing rolls them back.

### Fix

Wrap the deploy in a `begin/rescue` that calls `accessories_manager_for(pr_number).remove_all` and `@db_manager.teardown(pr_number: pr_number)` on failure, then re-raise the error. Only do this if the destination file was successfully generated (to avoid removing unrelated things).

---

## Issue 6: Resource leak on failed remove

In `Deployer#remove`, if `accessories_manager.remove_all` raises, the destination file is never deleted.

### Fix

Move `@generator.cleanup(pr_number: pr_number)` into an `ensure` block, or restructure so cleanup always happens. The `rescue` block for `DeployError` should also attempt `generator.cleanup`.

---

## Issue 7: Template missing documented config keys

File: `templates/kamal-pull-preview.yml.erb`.

### Fix

Add commented-out examples for:

```yaml
# Accessories strategy: "auto" | "none" | list (default: "auto")
# accessories: auto

# Database seed dump (optional)
# db_seed:
#   source: "s3://my-bucket/dumps/latest.dump"
#   format: custom
#   required: false
#   table_check: true
```

Also add a comment about `idle_stop_minutes` being reserved.

---

## Issue 8: `DestinationGenerator#render` creates new `DatabaseManager` on every call

### Fix

Inject `db_manager` via constructor in `DestinationGenerator`, defaulting to `DatabaseManager.new(config: @config)`. Update `Deployer` to pass its `@db_manager` to the generator.

---

## Issue 9: No `AGENTS.md`

### Fix

Create `AGENTS.md` at the root with:
- Project overview (1 paragraph).
- How to run tests: `bundle exec rake spec`.
- Build: `bundle exec rake build`.
- Key conventions: `frozen_string_literal: true`, keyword args, one class per file under `lib/kamal_pull_preview/`.
- Dependencies: thor, sqlite3, tty-table, logger.
- CI matrix: Ruby 3.2–4.0.

---

## Verification Checklist

After all changes, verify:
- [ ] `bundle exec rake spec` passes (77+ examples, 0 failures).
- [ ] `bundle exec kamal-pull-preview init` in a temp dir generates a file with the new template content.
- [ ] `bundle exec rubocop` or similar linting passes (if available).
- [ ] GitHub Actions workflow syntax is valid (check with `actionlint` if available, or at least eyeball it).

---

## Constraints

- **Do not** change the public CLI interface (commands, options, or output format).
- **Do not** break backward compatibility with existing `kamal-pull-preview.yml` files.
- Keep each class in its own file under `lib/kamal_pull_preview/`.
- Use `frozen_string_literal: true` in all new files.
- Follow existing error-handling patterns (`ConfigError`, `DeployError`, `DbError`, `StateError`).
