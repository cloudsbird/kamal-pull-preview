# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.1.0] - 2026-04-30

### Added
- `deploy` command: generates Kamal 2.x destination override and deploys a PR preview
- `remove` command: tears down a PR preview and cleans up destination file
- `list` command: displays all active previews from SQLite state store
- SQLite-backed state tracking at `~/.kamal-pull-preview/state.db`
- Kamal 2.x destination override generator (`.kamal/destinations/pr-{N}.yml`)
- `kamal-pull-preview.yml` configuration file support
- GitHub Actions workflow template at `templates/github-action.yml.erb`
- RSpec test suite with CI matrix for Ruby 3.2 and 3.3
