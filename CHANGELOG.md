# Changelog

## Unreleased

### Added

- **Database seeding (`db_seed`)** — restore preview databases from S3, HTTPS, local files, or shell commands before the app boots.
  - `DumpFetcher` supports `s3://`, `https://`, `http://`, bare file paths, and `cmd:` sources.
  - Auto-detects PostgreSQL dump format (`custom`, `plain`, `directory`) from magic bytes.
  - `table_check` skips restore when the target already has tables.
  - `required` aborts deploy if the source is unreachable.
- **Accessories support** — PR-scoped accessory containers (redis, postgres, mysql, etc.) with automatic port remapping.
  - `accessories: auto` reads accessory definitions from `config/deploy.yml`.
  - `accessories: none` skips all accessories.
  - `accessories: [list]` allow-lists specific accessories.
- **`idle_stop_minutes` config key** — reserved for future auto-stop behavior (currently documented but inactive).
- **`AGENTS.md`** — contributor guide for coding agents.

### Fixed

- **Resource leaks on failed deploy** — if `kamal deploy` fails, accessories and the database are now torn down automatically before re-raising the error.
- **Resource leaks on failed remove** — destination files are now cleaned up in an `ensure` block so they are never left behind.
- **`DestinationGenerator`** no longer creates a new `DatabaseManager` on every `#render` call; it is now injected via the constructor.

### Changed

- Template (`templates/kamal-pull-preview.yml.erb`) now includes commented examples for `accessories` and `db_seed`.
- `.gitignore` now excludes `.ruby-lsp/`.

## 0.1.1 (2026-04-30)

- Added `postgresql` database strategy. Each PR preview now gets an isolated PostgreSQL database (`pr_{number}`) with automatic create-on-deploy and drop-on-remove lifecycle.
- Added PostgreSQL configuration keys: `pg_host`, `pg_port` (default 5432), `pg_user`, `pg_password`.
- Added `DbError` exception class for database operation failures.
- `DATABASE_URL` is automatically injected into Kamal destination files when using the `postgresql` strategy.

## 0.1.0 (2026-04-30)

- Initial release
