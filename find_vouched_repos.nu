#!/usr/bin/env nu
# find_vouched_repos.nu
#
# Find repositories containing VOUCHED.td using GitHub Search Code API.
# Uses GITHUB_TOKEN from env or .env.

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
    "User-Agent": "nu-vouch-repo-finder"
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

def search_code_page [token: string, query: string, per_page: int, page: int] {
  let q = ($query | url encode)
  let url = $"https://api.github.com/search/code?q=($q)&per_page=($per_page)&page=($page)"

  mut attempts = 0
  mut out = null
  loop {
    $attempts = ($attempts + 1)
    let resp = (http get --full --allow-errors --headers (gh_headers $token) $url)

    if $resp.status == 200 {
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

def extract_rows [items: list] {
  $items
  | each {|it|
    {
      repo: $it.repository.full_name
      path: $it.path
      html_url: ($it.html_url? | default "")
      api_url: ($it.url? | default "")
      sha: ($it.sha? | default "")
    }
  }
}

def main [
  --query: string = "filename:VOUCHED.td"
  --out: string = "vouch_repos.csv"
  --max-pages: int = 10
  --per-page: int = 100
] {
  if $per_page > 100 {
    error make { msg: "--per-page cannot exceed 100 for GitHub Search API" }
  }

  let token = (get_token)
  let max_pages_capped = (if $max_pages > 10 { 10 } else { $max_pages })
  mut page = 1
  mut rows = []
  mut total_count = 0
  mut incomplete_results = false

  loop {
    if $page > $max_pages_capped { break }

    let resp = (search_code_page $token $query $per_page $page)

    if $resp.status != 200 {
      let message = ($resp.body.message? | default "Unknown GitHub error")
      let status_s = ($resp.status | into string)
      error make { msg: ("GitHub API error (status=" + $status_s + "): " + $message) }
    }

    if $page == 1 {
      $total_count = ($resp.body.total_count? | default 0)
      $incomplete_results = ($resp.body.incomplete_results? | default false)
    }

    let items = ($resp.body.items? | default [])
    if ($items | length) == 0 { break }

    $rows = ($rows | append (extract_rows $items) | flatten)

    if ($items | length) < $per_page { break }
    $page = ($page + 1)
  }

  let final = (
    $rows
    | uniq-by repo path
    | sort-by repo path
  )

  $final | to csv | save -f $out

  let fetched_cap = ($max_pages_capped * $per_page)
  {
    saved_to: $out
    query: $query
    rows: ($final | length)
    total_count: $total_count
    incomplete_results: $incomplete_results
    max_pages_used: $max_pages_capped
    per_page: $per_page
    api_fetch_cap: $fetched_cap
    note: (if $total_count > $fetched_cap { "More results exist than fetched; increase sharding or pages (up to API cap 1000)." } else { "" })
  }
}
