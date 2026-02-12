# AGENTS

This repository builds and serves a static “Vouch Book” from GitHub vouch data.

## Goal

Generate a ranked user reputation view from `VOUCHED.td` files across repositories.

## Data Flow

1. Discover repos with vouch files:
   - `find_vouched_repos.nu` -> `vouch_repos.csv`
2. Enrich repos and extract users:
   - `enrich_vouched_repos.nu` -> `vouch_repo_stats.csv`, `vouch_repo_users.csv`
3. Build site payload:
   - `build_vouch_book_data.nu` -> `site/data/vouch_book.json`
4. Serve static site:
   - `site/index.html`, `site/styles.css`, `site/app.js`

Use `refresh_vouch_book.nu` to run all steps.

## Required Env

- `GITHUB_TOKEN` (env or `.env`)

Token must allow API search and repository content reads for target repos.

## Core Commands

Full run:

```bash
nu ./refresh_vouch_book.nu --query 'filename:VOUCHED.td' --max-pages 10 --per-page 100
```

Site preview:

```bash
python3 -m http.server 8000
# http://localhost:8000/site/
```

## Conventions

- Keep outputs deterministic and CSV/JSON-based.
- Preserve static-site-only architecture (no backend runtime).
- Keep parsing tolerant of:
  - `user`
  - `platform:user`
  - `-user` / `-platform:user` (denounced)

## Known Constraints

- GitHub REST code search has:
  - legacy search behavior (may differ from UI)
  - query result cap of 1000 items
  - strict rate limits
- Scripts should back off on rate-limit responses and fail clearly on auth issues.

## If Extending

- Add query sharding when `total_count > 1000`.
- Add GitHub Actions workflow to refresh data and publish `site/`.
- Keep the site data contract stable:
  - `site/data/vouch_book.json` should continue exposing `totals`, `users`, `repos`.
