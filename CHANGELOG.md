# Changelog

## 0.1.1 (2026-04-30)

- Added `postgresql` database strategy. Each PR preview now gets an isolated PostgreSQL database (`pr_{number}`) with automatic create-on-deploy and drop-on-remove lifecycle.
- Added PostgreSQL configuration keys: `pg_host`, `pg_port` (default 5432), `pg_user`, `pg_password`.
- Added `DbError` exception class for database operation failures.
- `DATABASE_URL` is automatically injected into Kamal destination files when using the `postgresql` strategy.

## 0.1.0 (2026-04-30)

- Initial release
