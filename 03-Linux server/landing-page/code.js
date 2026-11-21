/* ==========================================================
   Northstar Solutions - Internal IT Portal
   Shared script. Each feature only runs if its elements exist
   on the current page, so one file serves every page.

   Sections:
   1. Helpers
   2. Navigation (highlight current page)
   3. Footer info
   4. Server status (reads status.json)
   5. Ticket helper (priority + Markdown ticket)
   6. Copy-to-clipboard buttons
   ========================================================== */

"use strict";

/* ---------- 1. Helpers ---------- */

/** Shorthand for document.querySelector. */
const $ = (selector, root = document) => root.querySelector(selector);

/** Shorthand for document.querySelectorAll, returned as a real array. */
const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

/** Map a service/state word to a CSS class (ok / warn / bad). */
function stateClass(state) {
  const s = String(state).toLowerCase();
  if (s === "active" || s === "running" || s === "ok") return "ok";
  if (s === "inactive" || s === "failed" || s === "dead") return "bad";
  return "warn";
}

/** Safely set text. Using textContent avoids injecting HTML from status.json. */
function setText(el, text) {
  if (el) el.textContent = text;
}

/** Format an ISO date string for display. Returns the original text if invalid. */
function formatDate(iso) {
  const d = new Date(iso);
  return isNaN(d) ? String(iso) : d.toLocaleString();
}


/* ---------- 2. Navigation ---------- */

function highlightCurrentPage() {
  // Last part of the URL path; an empty value means the site root (index.html).
  const current = location.pathname.split("/").pop() || "index.html";
  $$(".nav a").forEach((link) => {
    if (link.getAttribute("href") === current) {
      link.setAttribute("aria-current", "page");
    }
  });
}


/* ---------- 3. Footer info ---------- */

function fillFooter() {
  setText($("#footer-host"), location.host || "local file");
  setText($("#footer-year"), new Date().getFullYear());
}


/* ---------- 4. Server status ---------- */

/**
 * Fetches status.json and measures how long the request took.
 * The JSON file is produced on the server by gen-status.sh (see README.md).
 * Returns { data, latencyMs }. Throws if the file can't be loaded.
 */
async function loadStatus() {
  const started = performance.now();
  // The timestamp in the URL stops the browser from using a cached copy.
  const response = await fetch(`status.json?t=${Date.now()}`, { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const data = await response.json();
  return { data, latencyMs: Math.round(performance.now() - started) };
}

/** Home page: small summary strip. */
function renderStatusStrip(data, latencyMs) {
  const allUp = data.services.every((s) => stateClass(s.state) === "ok");

  const overall = $("#overall-status");
  if (overall) {
    overall.innerHTML = "";
    const dot = document.createElement("span");
    dot.className = `dot ${allUp ? "ok" : "warn"}`;
    overall.append(dot, allUp ? "All services running" : "Attention needed");
  }
  setText($("#strip-host"), data.hostname);
  setText($("#strip-latency"), `${latencyMs} ms`);
  setText($("#strip-updated"), formatDate(data.generated));
}

/** Status page: full detail (services table, disk bar, system facts). */
function renderStatusPage(data, latencyMs) {
  // System facts
  setText($("#sys-host"), data.hostname);
  setText($("#sys-os"), data.os);
  setText($("#sys-uptime"), data.uptime);
  setText($("#sys-latency"), `${latencyMs} ms`);
  setText($("#sys-generated"), formatDate(data.generated));

  // Disk usage bar
  const pct = Number(data.disk.percent);
  const bar = $("#disk-bar span");
  if (bar) {
    bar.style.width = `${Math.min(pct, 100)}%`;
    bar.className = pct >= 90 ? "bad" : pct >= 75 ? "warn" : "";
  }
  setText($("#disk-text"), `${data.disk.used_gb} GB used of ${data.disk.total_gb} GB (${pct}%)`);

  // Services table
  const body = $("#services-body");
  if (body) {
    body.innerHTML = "";
    data.services.forEach((svc) => {
      const row = document.createElement("tr");

      const name = document.createElement("td");
      name.textContent = svc.name;

      const unit = document.createElement("td");
      const code = document.createElement("code");
      code.textContent = svc.unit;
      unit.append(code);

      const state = document.createElement("td");
      const badge = document.createElement("span");
      badge.className = `badge ${stateClass(svc.state)}`;
      badge.textContent = svc.state;
      state.append(badge);

      const detail = document.createElement("td");
      detail.textContent = svc.detail;
      detail.className = "muted";

      row.append(name, unit, state, detail);
      body.append(row);
    });
  }
}

/** Shows an error message in every status container on the page. */
function showStatusError(error) {
  const message = `Could not load status.json (${error.message}). ` +
    "If you opened this file directly from disk, serve it through Nginx instead.";
  setText($("#status-error"), message);
  const box = $("#status-error");
  if (box) box.hidden = false;
  setText($("#overall-status"), "Status unavailable");
}

async function initStatus() {
  const needsStatus = $("#overall-status") || $("#services-body");
  if (!needsStatus) return;

  // Give visible feedback on the status page's refresh button (if present)
  const refresh = $("#refresh-status");
  if (refresh) {
    refresh.disabled = true;
    refresh.textContent = "Refreshing...";
  }

  try {
    const { data, latencyMs } = await loadStatus();
    const errorBox = $("#status-error");
    if (errorBox) errorBox.hidden = true;   // clear an old error after a good load
    renderStatusStrip(data, latencyMs);
    renderStatusPage(data, latencyMs);
  } catch (error) {
    showStatusError(error);
  }

  // Short pause so the "Refreshing..." state is actually visible
  await new Promise((resolve) => setTimeout(resolve, 400));

  if (refresh) {
    refresh.disabled = false;
    refresh.textContent = "Refresh now";
  }
  // Time of the last check made by this browser (not the same as "Data generated")
  setText($("#last-checked"), `Last checked: ${new Date().toLocaleTimeString()}`);
}

/** Status page: refresh button and automatic refresh every 60 seconds. */
function initRefresh() {
  const refresh = $("#refresh-status");
  if (!refresh) return;
  refresh.addEventListener("click", initStatus);
  setInterval(initStatus, 60 * 1000);
}


/* ---------- 5. Ticket helper (help desk page) ---------- */

// Matches the priority table on helpdesk.html.
// Score = impact + urgency (each 1-3).  5-6 High, 4 Medium, 2-3 Low.
const LEVELS = { low: 1, medium: 2, high: 3 };

function calculatePriority(impact, urgency) {
  const score = LEVELS[impact] + LEVELS[urgency];
  if (score >= 5) return "High";
  if (score === 4) return "Medium";
  return "Low";
}

/** Ticket numbers continue from NS-008 (the last ticket in the project guide). */
const FIRST_NEW_TICKET = 9;

function nextTicketId() {
  let n = FIRST_NEW_TICKET;
  try {
    const stored = Number(localStorage.getItem("ns-next-ticket"));
    if (stored >= FIRST_NEW_TICKET) n = stored;
  } catch (e) { /* storage may be blocked; fall back to default */ }
  return n;
}

function saveNextTicket(n) {
  try { localStorage.setItem("ns-next-ticket", String(n)); } catch (e) { /* ignore */ }
}

function buildTicketMarkdown(form, id, priority) {
  const value = (name) => form.elements[name].value.trim() || "-";
  const today = new Date().toISOString().slice(0, 10);

  return [
    `# NS-${String(id).padStart(3, "0")} - ${value("summary")}`,
    "",
    `| Field | Value |`,
    `|---|---|`,
    `| Date | ${today} |`,
    `| User | ${value("user")} |`,
    `| Department | ${value("department")} |`,
    `| Category | ${value("category")} |`,
    `| Impact | ${value("impact")} |`,
    `| Urgency | ${value("urgency")} |`,
    `| Priority | ${priority} |`,
    `| Status | New |`,
    "",
    "## Description (from the employee)",
    value("description"),
    "",
    "## Business impact",
    "-",
    "",
    "## Troubleshooting performed (internal)",
    "-",
    "",
    "## Root cause (internal, once established)",
    "-",
    "",
    "## Resolution",
    "-",
    "",
    "## Verification",
    "-",
    "",
    "## Message to employee",
    "-",
    ""
  ].join("\n");
}

function initTicketHelper() {
  const form = $("#ticket-form");
  if (!form) return;

  const badge = $("#priority-badge");
  const output = $("#ticket-output");

  function updatePriority() {
    const priority = calculatePriority(form.elements.impact.value, form.elements.urgency.value);
    badge.textContent = priority;
    badge.className = `badge ${priority.toLowerCase()}`;
    return priority;
  }

  form.addEventListener("change", updatePriority);
  updatePriority();

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const id = nextTicketId();
    output.value = buildTicketMarkdown(form, id, updatePriority());
    saveNextTicket(id + 1);
    $("#ticket-output-wrap").hidden = false;
    output.focus();
  });

  $("#reset-ticket-counter")?.addEventListener("click", () => {
    saveNextTicket(FIRST_NEW_TICKET);
    setText($("#counter-msg"), `Next ticket will be NS-${String(FIRST_NEW_TICKET).padStart(3, "0")}.`);
  });

  $("#copy-ticket")?.addEventListener("click", (event) => copyText(output.value, event.target));
}


/* ---------- 6. Copy-to-clipboard ---------- */

/** Copies text and briefly changes the button label to confirm. */
async function copyText(text, button) {
  const original = button.textContent;
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = "Copied";
  } catch (e) {
    // navigator.clipboard needs HTTPS or localhost. Plain HTTP on a lab IP may block it.
    button.textContent = "Select and copy manually";
  }
  setTimeout(() => { button.textContent = original; }, 1800);
}

function initCopyButtons() {
  $$(".codeblock").forEach((block) => {
    const button = $(".copy-btn", block);
    const code = $("pre", block);
    if (button && code) {
      button.addEventListener("click", () => copyText(code.innerText, button));
    }
  });
}


/* ---------- Start ---------- */

document.addEventListener("DOMContentLoaded", () => {
  highlightCurrentPage();
  fillFooter();
  initStatus();
  initRefresh();
  initTicketHelper();
  initCopyButtons();
});
