const state = {
  data: null,
  selectedKey: null,
  search: "",
  sortBy: "score",
  minRepos: 0,
};

const metricsEl = document.getElementById("metrics");
const bodyEl = document.getElementById("leaderboardBody");
const detailEl = document.getElementById("detailPanel");
const searchInput = document.getElementById("searchInput");
const sortSelect = document.getElementById("sortSelect");
const minReposInput = document.getElementById("minReposInput");

init();

async function init() {
  try {
    const res = await fetch("./data/vouch_book.json");
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    const data = await res.json();
    state.data = data;
    state.selectedKey = data.users[0]?.user_key ?? null;
    bindEvents();
    render();
  } catch (err) {
    document.body.innerHTML = `<main class="page"><p>Failed to load data file: <code>site/data/vouch_book.json</code></p><p>${escapeHtml(
      String(err)
    )}</p></main>`;
  }
}

function bindEvents() {
  searchInput.addEventListener("input", (e) => {
    state.search = e.target.value.trim().toLowerCase();
    render();
  });

  sortSelect.addEventListener("change", (e) => {
    state.sortBy = e.target.value;
    render();
  });

  minReposInput.addEventListener("input", (e) => {
    const parsed = Number.parseInt(e.target.value, 10);
    state.minRepos = Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
    render();
  });
}

function render() {
  renderMetrics();
  renderTable();
  renderDetail();
}

function renderMetrics() {
  const d = state.data;
  const items = [
    ["Updated", formatDate(d.generated_at)],
    ["Repos", d.totals.repos.toLocaleString()],
    ["Users", d.totals.unique_users.toLocaleString()],
    ["Active Vouches", d.totals.active_edges.toLocaleString()],
    ["Denounced", d.totals.denounced_edges.toLocaleString()],
  ];

  metricsEl.innerHTML = items
    .map(
      ([label, value]) => `
      <article class="metric">
        <div class="metric-label">${escapeHtml(label)}</div>
        <div class="metric-value">${escapeHtml(String(value))}</div>
      </article>`
    )
    .join("");
}

function filteredUsers() {
  const q = state.search;
  let users = state.data.users.filter((u) => {
    if (u.active_repo_count < state.minRepos) return false;
    if (!q) return true;
    return (
      u.user.toLowerCase().includes(q) ||
      u.user_key.toLowerCase().includes(q)
    );
  });

  users = users.slice().sort((a, b) => {
    switch (state.sortBy) {
      case "user":
        return a.user.localeCompare(b.user);
      case "active_repo_count":
        return (
          b.active_repo_count - a.active_repo_count ||
          b.score - a.score ||
          a.user.localeCompare(b.user)
        );
      case "stars_total":
        return (
          b.stars_total - a.stars_total ||
          b.score - a.score ||
          a.user.localeCompare(b.user)
        );
      case "score":
      default:
        return b.score - a.score || a.user.localeCompare(b.user);
    }
  });

  return users;
}

function renderTable() {
  const users = filteredUsers();

  if (users.length === 0) {
    bodyEl.innerHTML = `
      <tr><td colspan="6">No users match the current filters.</td></tr>
    `;
    return;
  }

  if (!users.some((u) => u.user_key === state.selectedKey)) {
    state.selectedKey = users[0].user_key;
  }

  bodyEl.innerHTML = users
    .map((u, idx) => {
      const selectedClass = u.user_key === state.selectedKey ? "is-selected" : "";
      return `
        <tr class="${selectedClass}" data-key="${escapeHtml(u.user_key)}">
          <td>${idx + 1}</td>
          <td>${escapeHtml(u.user)}</td>
          <td class="score">${u.score.toFixed(2)}</td>
          <td>${u.active_repo_count}</td>
          <td class="${u.denounced_repo_count > 0 ? "denounced" : ""}">${
            u.denounced_repo_count
          }</td>
          <td>${u.stars_total.toLocaleString()}</td>
        </tr>
      `;
    })
    .join("");

  bodyEl.querySelectorAll("tr[data-key]").forEach((row) => {
    row.addEventListener("click", () => {
      state.selectedKey = row.dataset.key;
      render();
    });
  });
}

function renderDetail() {
  const users = filteredUsers();
  const selected = users.find((u) => u.user_key === state.selectedKey);

  if (!selected) {
    detailEl.innerHTML = `<p class="detail-empty">Select a user to inspect vouch sources.</p>`;
    return;
  }

  detailEl.innerHTML = `
    <div class="detail-header">
      <h2 class="detail-name">${escapeHtml(selected.user)}</h2>
      <div class="score">${selected.score.toFixed(2)}</div>
    </div>
    <p class="repo-meta">
      ${selected.active_repo_count} active repos, ${
    selected.denounced_repo_count
  } denounced, ${selected.stars_total.toLocaleString()} weighted stars.
    </p>
    <ul class="repo-list">
      ${selected.repos
        .map((r) => {
          const status = r.denounced
            ? `<span class="denounced">denounced</span>`
            : `<span>active</span>`;
          const repoUrl = `https://github.com/${encodeURIComponent(r.repo).replace(
            "%2F",
            "/"
          )}`;
          return `
            <li class="repo-item">
              <div class="repo-top">
                <a class="repo-name" href="${repoUrl}" target="_blank" rel="noreferrer">${escapeHtml(
            r.repo
          )}</a>
                <span>${status}</span>
              </div>
              <div class="repo-meta">
                ${r.stars.toLocaleString()} stars • ${escapeHtml(
            r.path
          )} • ${escapeHtml(r.raw_entry)}
              </div>
            </li>
          `;
        })
        .join("")}
    </ul>
  `;
}

function formatDate(iso) {
  try {
    const d = new Date(iso);
    return `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`;
  } catch {
    return iso;
  }
}

function escapeHtml(s) {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
