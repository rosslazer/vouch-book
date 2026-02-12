#!/usr/bin/env nu
# build_vouch_book_data.nu
#
# Build site/data/vouch_book.json from:
# - vouch_repo_stats.csv
# - vouch_repo_users.csv

def score_weight [stars: int] {
  (((($stars + 1) | into float) | math ln) + 1.0)
}

def as_bool [s: any] {
  let v = (($s | into string) | str downcase | str trim)
  ($v == "true" or $v == "1" or $v == "yes")
}

def main [
  --repos-csv: string = "vouch_repo_stats.csv"
  --users-csv: string = "vouch_repo_users.csv"
  --out: string = "site/data/vouch_book.json"
] {
  if not ($repos_csv | path exists) {
    error make { msg: $"Missing repos CSV: ($repos_csv)" }
  }
  if not ($users_csv | path exists) {
    error make { msg: $"Missing users CSV: ($users_csv)" }
  }

  let repos = (open $repos_csv)
  let users_raw = (open $users_csv)

  let edges = (
    $users_raw
    | each {|r|
      {
        repo: $r.repo
        path: $r.path
        stars: ($r.stars | into int)
        platform: (($r.platform | default "github") | str downcase)
        user: ($r.user | str trim)
        denounced: (as_bool $r.denounced)
        raw_entry: ($r.raw_entry | default "")
      }
    }
    | where user != ""
    | uniq-by repo platform user denounced
  )

  let grouped = (
    $edges
    | group-by {|e| $"($e.platform):($e.user | str downcase)" }
    | items {|k, v| { user_key: $k, entries: $v } }
  )

  let users = (
    $grouped
    | each {|g|
      let entries = $g.entries
      let active = ($entries | where denounced == false)
      let denied = ($entries | where denounced == true)

      let active_weights = ($active | each {|e| score_weight $e.stars })
      let denied_weights = ($denied | each {|e| ((score_weight $e.stars) * 0.6) })

      let active_sum = (if (($active_weights | length) == 0) { 0.0 } else { $active_weights | math sum })
      let denied_sum = (if (($denied_weights | length) == 0) { 0.0 } else { $denied_weights | math sum })
      let score_raw = ($active_sum - $denied_sum)
      let score = ($score_raw | math round --precision 2)

      let active_repo_count = (
        if (($active | length) == 0) { 0 } else { $active | get repo | uniq | length }
      )
      let denounced_repo_count = (
        if (($denied | length) == 0) { 0 } else { $denied | get repo | uniq | length }
      )
      let stars_total = (
        if (($active | length) == 0) { 0 } else { $active | get stars | math sum }
      )

      {
        user_key: $g.user_key
        platform: ($entries | get platform | first)
        user: ($entries | get user | first)
        score: $score
        stars_total: $stars_total
        active_repo_count: $active_repo_count
        denounced_repo_count: $denounced_repo_count
        repos: (
          $entries
          | sort-by stars --reverse
          | each {|e|
              {
                repo: $e.repo
                path: $e.path
                stars: $e.stars
                denounced: $e.denounced
                raw_entry: $e.raw_entry
              }
            }
        )
      }
    }
    | sort-by score --reverse
  )

  let top_repos = (
    $repos
    | sort-by stars --reverse
    | each {|r|
      {
        repo: $r.repo
        path: $r.path
        stars: $r.stars
        active_users: $r.active_users
        denounced_users: $r.denounced_users
        vouch_file_url: $r.vouch_file_url
      }
    }
  )

  let payload = {
    generated_at: (date now | format date "%Y-%m-%dT%H:%M:%S%:z")
    totals: {
      repos: ($top_repos | length)
      unique_users: ($users | length)
      active_edges: ($edges | where denounced == false | length)
      denounced_edges: ($edges | where denounced == true | length)
    }
    users: $users
    repos: $top_repos
  }

  mkdir ($out | path dirname)
  $payload | to json --indent 2 | save -f $out

  {
    saved_to: $out
    users: ($users | length)
    repos: ($top_repos | length)
    active_edges: ($edges | where denounced == false | length)
    denounced_edges: ($edges | where denounced == true | length)
  }
}
