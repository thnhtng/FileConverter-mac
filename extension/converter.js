// Runs the jobs passed in ?jobs=[{url, kind, to, name, blocked}] :
// fetch the media (extension pages may fetch cross-origin thanks to
// host_permissions), convert with the shared web engine, save with
// chrome.downloads. `to` empty = save the original as-is.
import { convert, extensionOf, outputName, isFFmpegLoaded } from "./web/engine.js";
import { fileNameFromUrl, extFromType, isUnfetchable, isProtectedHost, LABELS } from "./shared.js";
import { getLang, makeT } from "./i18n.js";

const t = makeT(await getLang());
document.documentElement.lang = (await getLang());
document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });

const params = new URLSearchParams(location.search);
const page = params.get("page") || "";
let jobs = [];
try { jobs = JSON.parse(params.get("jobs") || "[]"); } catch (e) { jobs = []; }
const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const list = document.getElementById("jobs");

jobs.forEach((job, i) => {
  job.id = i;
  job.blocked = job.blocked || isUnfetchable(job.url) || (job.kind !== "image" && isProtectedHost(page));
  job.label = job.name || fileNameFromUrl(job.url, job.kind);
  list.insertAdjacentHTML("beforeend", `<li class="job" id="job-${i}">
    <div class="job-name"><b>${esc(job.label)}</b>${job.to ? ` → ${LABELS[job.to] || job.to.toUpperCase()}` : ""}</div>
    <div class="job-status muted" id="status-${i}"></div>
    <div class="bar"><i id="bar-${i}"></i></div></li>`);
});

function status(job, text, cls = "") {
  const el = document.getElementById("status-" + job.id);
  el.textContent = text; el.className = "job-status " + (cls || "muted");
}
function bar(job, f) { document.getElementById("bar-" + job.id).style.width = Math.round(Math.max(0, Math.min(1, f)) * 100) + "%"; }
const mb = (n) => (n / 1048576).toFixed(n < 10485760 ? 1 : 0) + " MB";

async function fetchWithProgress(job) {
  const res = await fetch(job.url, { credentials: "include" });
  if (!res.ok) throw new Error("HTTP " + res.status);
  const total = +res.headers.get("content-length") || 0;
  const type = res.headers.get("content-type") || "";
  if (!res.body) return { blob: await res.blob(), type };
  const reader = res.body.getReader();
  const chunks = []; let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value); got += value.length;
    status(job, t("fetching", { p: total ? Math.round((got / total) * 100) + "%" : mb(got) }));
    if (total) bar(job, (got / total) * (job.to ? 0.3 : 1));
  }
  return { blob: new Blob(chunks, { type }), type };
}

function save(blob, filename) {
  const url = URL.createObjectURL(blob);
  return new Promise((resolve, reject) => {
    chrome.downloads.download({ url, filename, saveAs: false }, (id) => {
      if (chrome.runtime.lastError || id === undefined) reject(new Error(chrome.runtime.lastError?.message || "download failed"));
      else { setTimeout(() => URL.revokeObjectURL(url), 60_000); resolve(id); }
    });
  });
}

let ok = 0;
for (const job of jobs) {
  if (job.blocked) { status(job, t("blocked"), "err"); continue; }
  try {
    const { blob, type } = await fetchWithProgress(job);
    // Fix names without a usable extension ("image.php", "media?id=3").
    let name = job.label;
    const typeExt = extFromType(type);
    if (typeExt && extensionOf(name) !== typeExt && !/^(jpg|jpeg|png|webp|gif|mp4|webm|mov|mp3|wav|ogg|flac|m4a|aac)$/.test(extensionOf(name))) {
      name = name.replace(/\.[^.]*$/, "") + "." + typeExt;
    }
    if (!job.to) {
      await save(blob, name);
      bar(job, 1); status(job, t("saved", { name }), "ok"); ok++;
      continue;
    }
    const result = await convert(blob, name, job.to, {
      onStage: (s) => { if (s === "engine" && !isFFmpegLoaded()) status(job, t("loadingEngine")); },
      onProgress: (p) => { bar(job, 0.3 + p * 0.7); status(job, t("converting", { p: Math.round(p * 100) })); },
    });
    const outName = outputName(name, job.to);
    await save(result.blob, outName);
    bar(job, 1); status(job, t("saved", { name: outName }), "ok"); ok++;
  } catch (e) {
    status(job, t("failed", { msg: String(e && e.message ? e.message : e).slice(0, 200) }), "err");
  }
}
const summary = document.getElementById("summary");
summary.textContent = t("allDone", { ok, n: jobs.length });
summary.dataset.done = "true";
