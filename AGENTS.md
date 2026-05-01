# AGENTS.md

## Project Overview

`kamal-pull-preview` is a Ruby gem that automates per-PR preview environments using Kamal 2.x. It generates Kamal destination override files for each pull request, manages database lifecycle (PostgreSQL schemas, SQLite volumes), handles accessory containers, and provides a CLI for deploying and removing previews. Each PR preview is deployed to a dedicated subdomain (e.g. `pr-42.preview.example.com`) on a shared host.

## Running Tests

```
bundle exec rake spec
```

All specs live under `spec/kamal_pull_preview/` and `spec/integration/`. The full suite currently contains 77+ examples.

## Building the Gem

```
bundle exec rake build
```

## Key Conventions

- All source files must include `# frozen_string_literal: true` at the top.
- Use keyword arguments for all public methods.
- One class per file, located under `lib/kamal_pull_preview/`.
- Follow existing error-handling patterns: `ConfigError`, `DeployError`, `DbError`, `StateError`.
- New files must be `require_relative`-loaded in `lib/kamal_pull_preview.rb`.

## Dependencies

| Gem        | Purpose                                      |
|------------|----------------------------------------------|
| thor       | CLI framework                                |
| sqlite3    | Local state store (SQLite-backed JSON rows)  |
| tty-table  | Tabular output for `list` command            |
| logger     | Structured log output                        |

## CI Matrix

The GitHub Actions workflow tests against Ruby versions **3.2**, **3.3**, **3.4**, and **4.0**.
