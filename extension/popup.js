import { collectMedia } from "./collect.js";
import { TARGETS, LABELS, isProtectedHost, isUnfetchable, fileNameFromUrl } from "./shared.js";
import { getLang, setLang, makeT, LANGS } from "./i18n.js";

let lang = await getLang();
let t = makeT(lang);
const state = { tab: null, page: "", items: [], filter: "all", selected: new Set(), error: null, scanning: true };
const $ = (id) => document.getElementById(id);
const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

async function activeTab() {
  // ?tabId= lets tests (and a detached popup window) target a specific tab.
  const forced = new URLSearchParams(location.search).get("tabId");
  if (forced) return chrome.tabs.get(+forced);
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function scan() {
  state.scanning = true; render();
  try {
    state.tab = await activeTab();
    const [res] = await chrome.scripting.executeScript({ target: { tabId: state.tab.id, allFrames: false }, func: collectMedia });
    const data = res?.result || { items: [], page: state.tab.url };
    state.page = data.page;
    const protectedPage = isProtectedHost(state.page);
    state.items = data.items.map((it, i) => ({
      ...it, id: i,
      name: fileNameFromUrl(it.url, it.kind),
      blocked: isUnfetchable(it.url) || (it.kind !== "image" && protectedPage),
    }));
  } catch (e) {
    state.error = t("cantScan");
  }
  state.scanning = false; render();
}

function visible() {
  return state.items.filter((i) => state.filter === "all" || i.kind === state.filter);
}

function render() {
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  $("lang").innerHTML = LANGS.map(([code, label]) => `<button type="button" data-lang="${code}" aria-pressed="${code === lang}">${label}</button>`).join("");

  const counts = { all: state.items.length, image: 0, video: 0, audio: 0 };
  state.items.forEach((i) => counts[i.kind]++);
  $("filters").innerHTML = [["all", "all"], ["image", "images"], ["video", "videos"], ["audio", "audio"]]
    .map(([k, label]) => `<button type="button" role="tab" data-filter="${k}" aria-selected="${state.filter === k}">${esc(t(label))} <span>${counts[k]}</span></button>`).join("");

  const protectedPage = isProtectedHost(state.page);
  $("notice").hidden = !protectedPage && !state.error;
  $("notice").textContent = state.error || (protectedPage ? t("protectedPage") : "");

  const list = $("list");
  if (state.scanning) { list.innerHTML = `<p class="empty">${esc(t("scanning"))}</p>`; }
  else if (!state.error && !visible().length) { list.innerHTML = `<p class="empty">${esc(t("none"))}</p>`; }
  else list.innerHTML = visible().map(itemHTML).join("");

  const selectable = visible().filter((i) => !i.blocked);
  const sel = [...state.selected].map((id) => state.items[id]).filter(Boolean);
  $("bulk").hidden = sel.length === 0;
  $("sel-count").textContent = t("selected", { n: sel.length });
  $("select-all").checked = selectable.length > 0 && selectable.every((i) => state.selected.has(i.id));
  $("select-all").disabled = !selectable.length;
  const kinds = [...new Set(sel.map((i) => i.kind))];
  const common = kinds.length ? TARGETS[kinds[0]].filter((x) => kinds.every((k) => TARGETS[k].includes(x))) : [];
  $("conv-selected").innerHTML = `<option value="">${esc(t("convertSelected"))}…</option>` + common.map((x) => `<option value="${x}">${LABELS[x]}</option>`).join("");
  $("conv-selected").disabled = !common.length;
}

function itemHTML(it) {
  const thumb = it.kind === "image"
    ? `<img src="${esc(it.url)}" alt="" loading="lazy" referrerpolicy="no-referrer">`
    : `<span class="kind-icon">${it.kind === "video" ? "🎬" : "🎵"}</span>`;
  const dims = it.w && it.h ? `${it.w}×${it.h}` : "";
  const dur = it.duration ? `${Math.round(it.duration)} s` : "";
  const meta = [it.kind === "image" ? t("images") : it.kind === "video" ? t("videos") : t("audio"), dims, dur].filter(Boolean).join(" · ");
  const controls = it.blocked
    ? `<span class="blocked small">🔒 ${esc(t("protectedItem"))}</span>`
    : `<button type="button" class="btn small" data-dl="${it.id}">${esc(t("download"))}</button>
       <select class="small" data-conv="${it.id}" aria-label="${esc(t("convertTo"))}"><option value="">${esc(t("convertTo"))}</option>${TARGETS[it.kind].map((x) => `<option value="${x}">${LABELS[x]}</option>`).join("")}</select>`;
  return `<div class="media ${it.blocked ? "is-blocked" : ""}">
    <input type="checkbox" data-sel="${it.id}" ${state.selected.has(it.id) ? "checked" : ""} ${it.blocked ? "disabled" : ""} aria-label="${esc(it.name)}">
    <div class="thumb">${thumb}</div>
    <div class="info"><div class="name" title="${esc(it.url)}">${esc(it.name)}</div><div class="small muted">${esc(meta)}</div><div class="controls">${controls}</div></div>
  </div>`;
}

function openConverter(jobs) {
  const params = new URLSearchParams({ jobs: JSON.stringify(jobs), page: state.page });
  chrome.tabs.create({ url: chrome.runtime.getURL("converter.html?" + params), index: state.tab ? state.tab.index + 1 : undefined });
}

document.addEventListener("click", async (e) => {
  const b = e.target.closest("button, a");
  if (!b) return;
  if (b.dataset.lang) { lang = b.dataset.lang; t = makeT(lang); await setLang(lang); render(); return; }
  if (b.dataset.filter) { state.filter = b.dataset.filter; render(); return; }
  if (b.dataset.dl) { const it = state.items[+b.dataset.dl]; chrome.downloads.download({ url: it.url, filename: it.name }); return; }
  if (b.id === "dl-selected") { for (const id of state.selected) { const it = state.items[id]; chrome.downloads.download({ url: it.url, filename: it.name }); } return; }
  if (b.id === "open-local") { e.preventDefault(); chrome.tabs.create({ url: chrome.runtime.getURL("web/index.html") }); }
});
document.addEventListener("change", (e) => {
  const el = e.target;
  if (el.dataset.sel) { el.checked ? state.selected.add(+el.dataset.sel) : state.selected.delete(+el.dataset.sel); render(); return; }
  if (el.dataset.conv && el.value) { const it = state.items[+el.dataset.conv]; openConverter([{ url: it.url, kind: it.kind, to: el.value, name: it.name }]); el.value = ""; return; }
  if (el.id === "select-all") { visible().filter((i) => !i.blocked).forEach((i) => (el.checked ? state.selected.add(i.id) : state.selected.delete(i.id))); render(); return; }
  if (el.id === "conv-selected" && el.value) { openConverter([...state.selected].map((id) => state.items[id]).map((it) => ({ url: it.url, kind: it.kind, to: el.value, name: it.name }))); el.value = ""; }
});

render();
scan();
