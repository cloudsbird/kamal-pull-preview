# kamal-pull-preview

[![Gem Version](https://img.shields.io/gem/v/kamal-pull-preview)](https://rubygems.org/gems/kamal-pull-preview)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Per-pull-request preview environments powered by **[Kamal 2.x](https://kamal-deploy.org/)**.

Every opened pull request gets its own live URL (`https://pr-42.preview.example.com`). When the PR is closed the environment is torn down automatically. State is tracked locally in SQLite so no extra infrastructure is needed.

Accessories defined in your `config/deploy.yml` (Redis, Sidekiq, etc.) are automatically discovered, scoped per-PR, and managed alongside the main deploy — no extra configuration required.

---

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration Reference](#configuration-reference)
- [CLI Reference](#cli-reference)
- [GitHub Actions Integration](#github-actions-integration)
- [Accessories Support](#accessories-support)
- [Database Strategies](#database-strategies)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- 🚀 **One command deploy** — `kamal-pull-preview deploy --pr 42 --sha abc1234 --repo owner/repo`
- 🔗 **Predictable URLs** — every PR gets `https://pr-{number}.{your-domain}`
- 📋 **State tracking** — SQLite database at `~/.kamal-pull-preview/state.db` tracks every active preview
- 🔧 **Automatic accessories** — Redis, Sidekiq, and any other Kamal accessory is auto-discovered from `config/deploy.yml`, scoped per-PR, and booted/removed alongside the main app
- 🐘 **Per-PR PostgreSQL** — each preview can get its own isolated database with automatic create/drop lifecycle
- ⏰ **TTL-based expiry** — previews are automatically cleaned up after a configurable number of hours
- 🔒 **Concurrency cap** — configurable maximum number of simultaneously running previews
- 🐙 **GitHub Actions ready** — drop-in workflow template included
- 💎 **Pure Ruby** — no Rails dependency, works in any Ruby project

---

## Prerequisites

| Requirement | Version |
|---|---|
| Ruby | ≥ 3.2 |
| [Kamal](https://kamal-deploy.org/) | 2.x (must be on `PATH`) |
| A server reachable over SSH | — |
| A Docker registry | — |
| PostgreSQL server & `psql` client | Optional — only needed for `db_strategy: "postgresql"` |

Kamal must already be configured in your project (`config/deploy.yml`) and able to deploy the main branch before you add previews.

---

## Installation

Add to your `Gemfile`:

```ruby
gem "kamal-pull-preview"
```

Then run:

```sh
bundle install
```

Or install it globally:

```sh
gem install kamal-pull-preview
```

---

## Quick Start

### 1. Create the config file

Copy the example config into your project root:

```sh
cat > kamal-pull-preview.yml << 'EOF'
host: "preview.example.com"
domain: "preview.example.com"
registry: "registry.example.com/myorg/myapp"
ttl_hours: 48
idle_stop_minutes: 240
max_concurrent: 15
db_strategy: "none"
EOF
```

**Using PostgreSQL?** See the [Database Strategies](#database-strategies) section for a full `postgresql` example.

See the [Configuration Reference](#configuration-reference) for all options.

### 2. Add the GitHub Actions workflow

Create `.github/workflows/pull-preview.yml` (you can use the template at `templates/github-action.yml.erb` as a starting point):

```yaml
name: Pull Preview

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.event.action != 'closed'
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle install
      - run: |
          bundle exec kamal-pull-preview deploy \
            --pr ${{ github.event.pull_request.number }} \
            --sha ${{ github.sha }} \
            --repo ${{ github.repository }}
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.KAMAL_REGISTRY_PASSWORD }}
          # Add any other secrets Kamal needs

  remove:
    runs-on: ubuntu-latest
    if: github.event.action == 'closed'
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle install
      - run: |
          bundle exec kamal-pull-preview remove \
            --pr ${{ github.event.pull_request.number }}
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.KAMAL_REGISTRY_PASSWORD }}
```

### 3. Done

Open a pull request — the workflow deploys a preview and prints the URL. Close the PR — the environment is removed.

---

## Configuration Reference

Place `kamal-pull-preview.yml` in your project root. All keys are at the top level.

```yaml
# SSH host where preview containers will be deployed (required).
# Must be reachable by the machine running kamal-pull-preview.
host: "preview.example.com"

# Base domain for preview URLs (required).
# Each PR gets a subdomain: pr-42.preview.example.com
domain: "preview.example.com"

# Docker registry prefix used by Kamal (required).
# Must match the "image" setting in your config/deploy.yml.
registry: "registry.example.com/myorg/myapp"

# Hours of inactivity before a preview is considered expired. Default: 48
ttl_hours: 48

# Minutes of inactivity before the container is stopped. Default: 240
idle_stop_minutes: 240

# Maximum number of simultaneously running previews. Default: 15
max_concurrent: 15

# Database strategy. Default: "none"
# Options: "none" | "sqlite" | "shared_schema" | "postgresql"
db_strategy: "none"

# Accessories strategy. Default: "auto"
# "auto"  — read accessories and server roles from config/deploy.yml (recommended)
# "none"  — skip all accessories entirely
# list    — explicit allowlist of accessory names to include
accessories: auto
# accessories: none
# accessories:
#   - redis

# PostgreSQL settings (only required when db_strategy is "postgresql")
# pg_host: "db.example.com"
# pg_port: 5432
# pg_user: "preview_admin"
# pg_password: "secret"
```

| Key | Required | Default | Description |
|---|---|---|---|
| `host` | ✅ | — | SSH host for the preview server |
| `domain` | ✅ | — | Base domain; PR URLs become `pr-N.{domain}` |
| `registry` | ✅ | — | Docker image registry prefix |
| `ttl_hours` | — | `48` | Hours until an inactive preview expires |
| `idle_stop_minutes` | — | `240` | Minutes of inactivity before auto-stop |
| `max_concurrent` | — | `15` | Maximum simultaneous active previews |
| `db_strategy` | — | `"none"` | Database isolation strategy (see [Database Strategies](#database-strategies)) |
| `accessories` | — | `"auto"` | Accessories strategy: `"auto"`, `"none"`, or a list (see [Accessories Support](#accessories-support)) |
| `pg_host` | when `db_strategy: postgresql` | — | PostgreSQL server host |
| `pg_port` | when `db_strategy: postgresql` | `5432` | PostgreSQL server port |
| `pg_user` | when `db_strategy: postgresql` | — | PostgreSQL user with CREATE/DROP DATABASE privileges |
| `pg_password` | when `db_strategy: postgresql` | — | PostgreSQL password |

---

## CLI Reference

```
kamal-pull-preview <command> [options]
```

### `deploy`

Builds and deploys a preview for the given pull request.

```sh
bundle exec kamal-pull-preview deploy \
  --pr 42 \
  --sha abc1234def5678 \
  --repo owner/repo
```

| Option | Required | Description |
|---|---|---|
| `--pr` | ✅ | Pull request number (integer) |
| `--sha` | ✅ | Git commit SHA to deploy |
| `--repo` | ✅ | Repository in `owner/repo` format |

Prints the preview URL on success:

```
Preview deployed: https://pr-42.preview.example.com
```

### `remove`

Tears down the preview for the given pull request.

```sh
bundle exec kamal-pull-preview remove --pr 42
```

| Option | Required | Description |
|---|---|---|
| `--pr` | ✅ | Pull request number (integer) |

### `list`

Lists all active previews tracked in the local state database.

```sh
bundle exec kamal-pull-preview list
```

Example output:

```
┌────┬─────────┬──────────────────────────────────────┬────────┬──────────────────────┐
│ PR │ SHA     │ URL                                  │ Status │ DeployedAt           │
├────┼─────────┼──────────────────────────────────────┼────────┼──────────────────────┤
│ 42 │ abc1234 │ https://pr-42.preview.example.com    │ active │ 2026-04-30T10:00:00Z │
│ 37 │ def5678 │ https://pr-37.preview.example.com    │ active │ 2026-04-29T08:30:00Z │
└────┴─────────┴──────────────────────────────────────┴────────┴──────────────────────┘
```

All commands exit with status `1` and print a red error message on failure.

---

## GitHub Actions Integration

The gem ships with a ready-to-use workflow template at `templates/github-action.yml.erb`. Copy it to `.github/workflows/pull-preview.yml` and adjust the environment variables to match your Kamal setup.

**Trigger events:**

| PR event | Action taken |
|---|---|
| `opened` | Deploy new preview |
| `synchronize` | Redeploy with latest commit |
| `reopened` | Redeploy |
| `closed` | Remove preview |

**Required secrets** (set in your repository's *Settings → Secrets and variables → Actions*):

- `KAMAL_REGISTRY_PASSWORD` — Docker registry credentials
- Any SSH key or other secret required by your Kamal configuration

---

## Accessories Support

kamal-pull-preview automatically reads `config/deploy.yml` and scopes every accessory (Redis, Sidekiq workers, etc.) to the PR being deployed. No manual configuration is needed beyond what is already in your Kamal config.

### How it works

On **deploy**, after writing the destination file, the gem:

1. Parses `config/deploy.yml` to discover `accessories:` and `servers:` roles.
2. Writes PR-scoped accessory definitions into `.kamal/destinations/pr-{N}.yml`.
3. Runs `kamal accessory boot pr-{N}-{name} -d pr-{N}` for each accessory.
4. Runs `kamal deploy -d pr-{N}` for the app itself.

On **remove**, after tearing down the app, the gem runs `kamal accessory remove pr-{N}-{name} -d pr-{N}` for every accessory.

### Accessory scoping

Each accessory gets a unique PR-prefixed name so it never conflicts with production or other previews:

| Original name | PR #42 scoped name |
|---|---|
| `redis` | `pr-42-redis` |
| `postgres` | `pr-42-postgres` |

### Port assignment

Ports are computed to be collision-free across concurrent PRs:

```
pr_port = original_port + 10_000 + (pr_number % 1_000)
```

**Example:** Redis default `6379` for PR #42 → `6379 + 10000 + 42 = 16421`

With `max_concurrent` defaulting to 15, the 1000-slot window provides plenty of headroom.

### Automatic env var injection

Known accessory types have their connection URLs injected automatically into the PR's env:

| Accessory name pattern | Env var injected |
|---|---|
| `/redis/i` | `REDIS_URL=redis://HOST:PR_PORT/0` |
| `/postgres\|pg/i` | `DATABASE_URL=postgres://postgres@HOST:PR_PORT/preview` |
| `/mysql/i` | `DATABASE_URL=mysql2://root@HOST:PR_PORT/preview` |

### Server roles

All `servers:` roles defined in `config/deploy.yml` (web, sidekiq, workers, etc.) are automatically included in the destination file. The `web` role gets a simple host list; all other roles get the `hosts:` format Kamal expects.

### Controlling accessories

The `accessories` key in `kamal-pull-preview.yml` has three modes:

```yaml
# Default: auto-discover from config/deploy.yml
accessories: auto

# Disable all accessory management
accessories: none

# Explicit allowlist — only boot these accessories per PR
accessories:
  - redis
```

### Generated destination file (with Redis + Sidekiq)

Given a `config/deploy.yml` with:

```yaml
servers:
  web:
    - 1.2.3.4
  sidekiq:
    hosts:
      - 1.2.3.4

accessories:
  redis:
    image: redis:7
    port: 6379
```

kamal-pull-preview generates `.kamal/destinations/pr-42.yml`:

```yaml
servers:
  web:
    - preview.example.com
  sidekiq:
    hosts:
      - preview.example.com

proxy:
  host: pr-42.preview.example.com

accessories:
  pr-42-redis:
    image: redis:7
    host: preview.example.com
    port: "16421"

env:
  clear:
    PULL_PREVIEW: "true"
    PR_NUMBER: "42"
    REDIS_URL: "redis://preview.example.com:16421/0"
```

### Backward compatibility

- If `config/deploy.yml` does not exist, accessories detection is silently skipped.
- If `accessories:` is absent from `deploy.yml`, no accessories section is written.
- The existing `db_strategy` key is unaffected.

---

## Database Strategies

The `db_strategy` setting controls how the database is handled for each preview environment.

| Strategy | Description |
|---|---|
| `none` | No database provisioned. Use this for stateless apps or apps that manage their own database. |
| `sqlite` | Each preview gets its own SQLite database file, volume-mounted into the container. |
| `shared_schema` | Previews share a Postgres instance; each PR gets an isolated schema (`pr_42`). |
| `postgresql` | Each preview gets its own isolated PostgreSQL database (`pr_42`) with automatic create/drop lifecycle. |

### PostgreSQL setup

When `db_strategy` is set to `"postgresql"`, the gem will:

1. **Create a database** named `pr_{number}` (e.g., `pr_42`) on deploy if it doesn't already exist.
2. **Inject `DATABASE_URL`** into the Kamal destination file so your app connects automatically.
3. **Drop the database** when the preview is removed.

**Requirements:**

- A PostgreSQL server reachable from the machine running `kamal-pull-preview`.
- The `psql` command-line client installed and on `PATH`.
- A PostgreSQL user with `CREATEDB` privileges (or pre-created databases with matching names).

**Example config:**

```yaml
host: "preview.example.com"
domain: "preview.example.com"
registry: "registry.example.com/myorg/myapp"
db_strategy: "postgresql"
pg_host: "db.example.com"
pg_port: 5432
pg_user: "preview_admin"
pg_password: "<%= ENV['PG_PASSWORD'] %>"
```

> **Tip:** You can use ERB in `kamal-pull-preview.yml` if you read it through ERB yourself, or keep secrets in environment variables and reference them in your GitHub Actions workflow.

> **Note:** `sqlite` and `shared_schema` strategies are scaffolded but their full implementation requires additional Kamal configuration in your project.

---

## How It Works

```
PR opened / pushed
       │
       ▼
kamal-pull-preview deploy
       │
       ├── Loads kamal-pull-preview.yml
       ├── Checks active preview count vs max_concurrent
       ├── Creates PostgreSQL database `pr_{N}` (when db_strategy = postgresql)
       ├── Writes .kamal/destinations/pr-{N}.yml
       │     (Kamal 2.x destination override with servers, proxy, accessories, env)
       ├── Runs: kamal accessory boot pr-{N}-{name} -d pr-{N}  (for each accessory)
       ├── Runs: kamal deploy -d pr-{N}
       └── Records preview in ~/.kamal-pull-preview/state.db

PR closed
       │
       ▼
kamal-pull-preview remove
       │
       ├── Runs: kamal remove -d pr-{N}
       ├── Runs: kamal accessory remove pr-{N}-{name} -d pr-{N}  (for each accessory)
       ├── Deletes .kamal/destinations/pr-{N}.yml
       ├── Drops PostgreSQL database `pr_{N}` (when db_strategy = postgresql)
       └── Removes record from state.db
```

Each PR destination file looks like (with Redis accessory and Sidekiq role):

```yaml
# .kamal/destinations/pr-42.yml
servers:
  web:
    - preview.example.com
  sidekiq:
    hosts:
      - preview.example.com
proxy:
  host: pr-42.preview.example.com
accessories:
  pr-42-redis:
    image: redis:7
    host: preview.example.com
    port: "16421"
env:
  clear:
    PULL_PREVIEW: "true"
    PR_NUMBER: "42"
    REDIS_URL: "redis://preview.example.com:16421/0"
```

> `DATABASE_URL` is only included when `db_strategy` is set to `"postgresql"` or a PostgreSQL/MySQL accessory is detected.
> The `accessories:` block and additional server roles are only present when discovered in `config/deploy.yml`.

This is a standard [Kamal 2.x destination override](https://kamal-deploy.org/docs/destinations) — no patching or monkey-patching of Kamal is involved.

**State database** is stored at `~/.kamal-pull-preview/state.db` (SQLite). The schema has a single `previews` table:

| Column | Type | Description |
|---|---|---|
| `pr_number` | INTEGER UNIQUE | Pull request number |
| `sha` | TEXT | Deployed commit SHA |
| `preview_url` | TEXT | Full HTTPS preview URL |
| `deployed_at` | TEXT | ISO 8601 timestamp of first deploy |
| `last_accessed_at` | TEXT | ISO 8601 timestamp of last deploy/update |
| `status` | TEXT | `active` or `removed` |

---

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/cloudsbird/kamal-pull-preview).

1. Fork the repository
2. Create a feature branch (`git checkout -b my-feature`)
3. Make your changes
4. Open a pull request

Please follow the existing code conventions: keyword arguments, `frozen_string_literal: true`, and keep each class in its own file under `lib/kamal_pull_preview/`.

---

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
