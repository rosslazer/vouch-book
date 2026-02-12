#!/usr/bin/env nu
# refresh_vouch_book.nu
#
# Full pipeline:
# 1) discover repos with VOUCHED.td
# 2) enrich with stars + parsed users
# 3) build static site JSON

def main [
  --query: string = "filename:VOUCHED.td"
  --max-pages: int = 10
  --per-page: int = 100
] {
  ^nu ./find_vouched_repos.nu --out vouch_repos.csv --query $query --max-pages $max_pages --per-page $per_page
  ^nu ./enrich_vouched_repos.nu --repos-csv vouch_repos.csv --out-repos vouch_repo_stats.csv --out-users vouch_repo_users.csv
  ^nu ./build_vouch_book_data.nu --repos-csv vouch_repo_stats.csv --users-csv vouch_repo_users.csv --out site/data/vouch_book.json

  {
    repos_csv: "vouch_repos.csv"
    repo_stats_csv: "vouch_repo_stats.csv"
    users_csv: "vouch_repo_users.csv"
    site_json: "site/data/vouch_book.json"
  }
}
