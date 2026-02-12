#!/usr/bin/env nu
# enrich_vouched_repos.nu
#
# Reads repos from vouch_repos.csv, then:
# - fetches repository stars from GitHub API
# - fetches VOUCHED.td content
# - extracts users from the vouch file
#
# Outputs:
# - repo-level CSV with stars and counts
# - user-level CSV with parsed users

def token_from_dotenv [dotenv_path: string = ".env"] {
  if not ($dotenv_path | path exists) {
    null
  } else {
    let line = (
      open $dotenv_path
      | lines
      | where {|l| ($l | str trim) !~ '^\s*#' }
      | where {|l| $l =~ '^\s*(export\s+)?GITHUB_TOKEN=' }
      | first
      | default null
    )

    if $line == null {
      null
    } else {
      (
        $line
        | str replace -r '^\s*export\s+' ''
        | str replace -r '^\s*GITHUB_TOKEN=' ''
        | str trim
        | str trim --char '"'
        | str trim --char "'"
      )
    }
  }
}

def get_token [] {
  let env_tok = ($env.GITHUB_TOKEN? | default "")
  if ($env_tok | str length) > 0 {
    $env_tok
  } else {
    let dot_tok = (token_from_dotenv ".env" | default "")
    if ($dot_tok | str length) > 0 {
      $dot_tok
    } else {
      error make { msg: "Missing GitHub token. Set GITHUB_TOKEN or add GITHUB_TOKEN=... in .env" }
    }
  }
}

def gh_headers [token: string] {
  {
    "User-Agent": "nu-vouch-repo-enricher"
    "Accept": "application/vnd.github+json"
    "X-GitHub-Api-Version": "2022-11-28"
    "Authorization": $"Bearer ($token)"
  }
}

def header_value [resp: record, key: string] {
  (
    $resp.headers.response
    | where {|h| ($h.name | str downcase) == ($key | str downcase) }
    | get value
    | first
    | default null
  )
}

def rate_limit_wait_seconds [resp: record] {
  let remaining_s = (header_value $resp "x-ratelimit-remaining" | default "")
  let reset_s = (header_value $resp "x-ratelimit-reset" | default "")

  if ($remaining_s == "" or $reset_s == "") {
    0
  } else {
    let remaining = (try { $remaining_s | into int } catch { 1 })
    if $remaining > 0 {
      0
    } else {
      let reset_epoch = (try { $reset_s | into int } catch { 0 })
      let now_epoch = (date now | format date "%s" | into int)
      let wait = ($reset_epoch - $now_epoch + 2)
      if $wait > 0 { $wait } else { 2 }
    }
  }
}

def gh_get [token: string, url: string] {
  mut attempts = 0
  mut out = null

  loop {
    $attempts = ($attempts + 1)
    let resp = (http get --full --allow-errors --headers (gh_headers $token) $url)

    if ($resp.status in [200, 404]) {
      $out = $resp
      break
    }

    if ($resp.status == 403 and $attempts <= 5) {
      let wait_s = (rate_limit_wait_seconds $resp)
      if $wait_s > 0 {
        sleep ($wait_s | into duration --unit sec)
        continue
      }

      let message = ($resp.body.message? | default "")
      if ($message | str downcase | str contains "secondary rate limit") {
        sleep 60sec
        continue
      }
    }

    if (($resp.status in [500, 502, 503, 504]) and $attempts <= 3) {
      sleep 3sec
      continue
    }

    $out = $resp
    break
  }

  $out
}

def decode_content [b64: string] {
  ($b64 | str replace -a "\n" "" | decode base64 | decode utf-8)
}

def parse_vouch_users [repo: string, path: string, stars: int, content: string] {
  $content
  | lines
  | each {|line|
      let trimmed = ($line | str trim)
      if ($trimmed == "" or ($trimmed | str starts-with "#")) {
        null
      } else {
        let raw_entry = ($trimmed | split row " " | first | str trim)
        if $raw_entry == "" {
          null
        } else {
          let denounced = ($raw_entry | str starts-with "-")
          let no_prefix = (if $denounced { $raw_entry | str substring 1.. } else { $raw_entry })
          let token = ($no_prefix | str trim | str trim --char "@")

          if $token == "" {
            null
          } else {
            let parsed = (
              if ($token | str contains ":") {
                let parts = ($token | split row ":")
                {
                  platform: (($parts | first | default "github") | str downcase)
                  user: ($parts | last | default "")
                }
              } else {
                {
                  platform: "github"
                  user: $token
                }
              }
            )

            if (($parsed.user | str trim) == "") {
              null
            } else {
              {
                repo: $repo
                path: $path
                stars: $stars
                platform: $parsed.platform
                user: ($parsed.user | str trim)
                denounced: $denounced
                raw_entry: $raw_entry
              }
            }
          }
        }
      }
    }
  | where $it != null
}

def fetch_vouch_file [token: string, repo: string, path: string] {
  let preferred_url = $"https://api.github.com/repos/($repo)/contents/($path)"
  let preferred = (gh_get $token $preferred_url)

  if $preferred.status == 200 {
    $preferred
  } else if $preferred.status == 404 {
    let alt_path = (if $path == ".github/VOUCHED.td" { "VOUCHED.td" } else { ".github/VOUCHED.td" })
    let alt_url = $"https://api.github.com/repos/($repo)/contents/($alt_path)"
    let alt = (gh_get $token $alt_url)
    if $alt.status == 200 { $alt } else { $preferred }
  } else {
    $preferred
  }
}

def main [
  --repos-csv: string = "vouch_repos.csv"
  --out-repos: string = "vouch_repo_stats.csv"
  --out-users: string = "vouch_repo_users.csv"
  --exclude-denounced
] {
  if not ($repos_csv | path exists) {
    error make { msg: $"Input file not found: ($repos_csv)" }
  }

  let token = (get_token)
  let repos = (open $repos_csv)

  mut repo_stats = []
  mut user_rows = []
  mut errors = []

  for row in $repos {
    let repo = ($row.repo? | default "")
    let path = ($row.path? | default ".github/VOUCHED.td")

    if $repo == "" {
      continue
    }

    let repo_url = $"https://api.github.com/repos/($repo)"
    let repo_resp = (gh_get $token $repo_url)

    if $repo_resp.status != 200 {
      $errors = ($errors | append [{
        repo: $repo
        step: "repo"
        status: $repo_resp.status
        message: ($repo_resp.body.message? | default "unknown")
      }])
      continue
    }

    let stars = ($repo_resp.body.stargazers_count? | default 0)
    let default_branch = ($repo_resp.body.default_branch? | default "")
    let repo_html_url = ($repo_resp.body.html_url? | default "")

    let vouch_resp = (fetch_vouch_file $token $repo $path)
    if $vouch_resp.status != 200 {
      $errors = ($errors | append [{
        repo: $repo
        step: "vouch_file"
        status: $vouch_resp.status
        message: ($vouch_resp.body.message? | default "unknown")
      }])
      continue
    }

    let vouch_path = ($vouch_resp.body.path? | default $path)
    let vouch_html_url = ($vouch_resp.body.html_url? | default "")
    let vouch_sha = ($vouch_resp.body.sha? | default "")
    let vouch_size = ($vouch_resp.body.size? | default 0)
    let content = (decode_content ($vouch_resp.body.content? | default ""))

    let parsed = (parse_vouch_users $repo $vouch_path $stars $content)
    let users_filtered = (if $exclude_denounced { $parsed | where denounced == false } else { $parsed })

    let active_count = ($parsed | where denounced == false | length)
    let denounced_count = ($parsed | where denounced == true | length)

    $repo_stats = ($repo_stats | append [{
      repo: $repo
      path: $vouch_path
      stars: $stars
      default_branch: $default_branch
      repo_url: $repo_html_url
      vouch_file_url: $vouch_html_url
      vouch_file_sha: $vouch_sha
      vouch_file_size: $vouch_size
      active_users: $active_count
      denounced_users: $denounced_count
      extracted_users: ($users_filtered | length)
    }])

    $user_rows = ($user_rows | append $users_filtered | flatten)
  }

  let repos_final = ($repo_stats | sort-by stars --reverse)
  let users_final = ($user_rows | sort-by repo user)
  let errs_final = ($errors | sort-by repo step)

  $repos_final | to csv | save -f $out_repos
  $users_final | to csv | save -f $out_users

  if ($errs_final | length) > 0 {
    let err_path = ($out_repos | str replace -r '\.csv$' '.errors.csv')
    $errs_final | to csv | save -f $err_path
  }

  {
    repos_in: ($repos | length)
    repos_written: ($repos_final | length)
    users_written: ($users_final | length)
    errors: ($errs_final | length)
    repos_out: $out_repos
    users_out: $out_users
    exclude_denounced: $exclude_denounced
  }
}
