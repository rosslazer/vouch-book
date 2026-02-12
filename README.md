# Vouch Book

Static reputation index built from GitHub `VOUCHED.td` files.

This project:
- Finds repos that contain `VOUCHED.td` using GitHub Search Code API
- Pulls repo metadata (stars) and vouch file contents
- Extracts vouched users (including denounced entries)
- Builds a static JSON dataset and static website leaderboard

## Prereqs

- Nushell (`nu`)
- A GitHub token in env or `.env`:

```bash
export GITHUB_TOKEN=...
# or in .env:
# export GITHUB_TOKEN=...
```

## Pipeline

Run the full refresh:

```bash
nu ./refresh_vouch_book.nu --query 'filename:VOUCHED.td' --max-pages 10 --per-page 100
```

This runs:
1. `find_vouched_repos.nu`
2. `enrich_vouched_repos.nu`
3. `build_vouch_book_data.nu`

## Scripts

- `find_vouched_repos.nu`
  - Queries GitHub Search Code API
  - Handles pagination and rate limits
  - Writes `vouch_repos.csv`

- `enrich_vouched_repos.nu`
  - Reads `vouch_repos.csv`
  - Fetches repo stars and vouch file contents
  - Extracts users from entries like `user`, `github:user`, `-user`
  - Writes:
    - `vouch_repo_stats.csv`
    - `vouch_repo_users.csv`
  - Optional: `--exclude-denounced`

- `build_vouch_book_data.nu`
  - Reads enriched CSVs
  - Computes per-user reputation score
  - Writes `site/data/vouch_book.json`

- `refresh_vouch_book.nu`
  - Convenience runner for all steps

## Site

Static frontend files:
- `site/index.html`
- `site/styles.css`
- `site/app.js`
- `site/data/vouch_book.json`

Run locally:

```bash
python3 -m http.server 8000
# open http://localhost:8000/site/
```

## Output Files

- `vouch_repos.csv`: repos/files found by search API
- `vouch_repo_stats.csv`: repo-level stats (stars, counts, URLs)
- `vouch_repo_users.csv`: extracted user-level edges
- `site/data/vouch_book.json`: compiled dataset used by UI

## Notes

- GitHub REST code search can differ from GitHub UI code search.
- Search API has a 1000-result cap per query; shard queries if needed.
- Rate limits are handled with backoff in Nu scripts.
