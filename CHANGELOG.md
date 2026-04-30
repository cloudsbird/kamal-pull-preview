# Changelog

## [0.1.0] - 2026-04-30

### Added

- Initial release of kamal-pull-preview
- `deploy` CLI command to spin up per-PR preview environments via Kamal 2.x
- `remove` CLI command to tear down a preview environment
- `list` CLI command to display all active previews in a table
- `init` CLI command to scaffold configuration files
- `cleanup` CLI command to remove expired preview environments
- SQLite-backed state tracking (`~/.kamal-pull-preview/state.db`)
- Destination-override YAML generation for Kamal 2.x (`.kamal/destinations/pr-N.yml`)
- Configurable TTL, max-concurrent-previews, and DB strategy via `kamal-pull-preview.yml`
- GitHub Actions workflow template for automated deploy/remove on PR events
