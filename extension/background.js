// Service worker: right-click menus on images/videos/audio/links.
// Conversion itself happens in converter.html (ffmpeg.wasm needs a page,
// not a short-lived worker).
import { TARGETS, LABELS, isProtectedHost, isUnfetchable } from "./shared.js";
import { getLang, makeT } from "./i18n.js";

const MEDIA_LINK = ["*://*/*.mp4*", "*://*/*.webm*", "*://*/*.mov*", "*://*/*.m4v*", "*://*/*.mp3*", "*://*/*.wav*", "*://*/*.ogg*", "*://*/*.flac*", "*://*/*.m4a*", "*://*/*.jpg*", "*://*/*.jpeg*", "*://*/*.png*", "*://*/*.webp*", "*://*/*.gif*"];

async function buildMenus() {
  const t = makeT(await getLang());
  await chrome.contextMenus.removeAll();
  const all = ["image", "video", "audio", "link"];
  chrome.contextMenus.create({ id: "fc-root", title: t("menuRoot"), contexts: all });
  chrome.contextMenus.create({ id: "fc-download", parentId: "fc-root", title: t("menuDownload"), contexts: all });
  chrome.contextMenus.create({ id: "fc-sep", parentId: "fc-root", type: "separator", contexts: all });
  // One entry per target; Chrome only shows the ones whose context matches
  // what was right-clicked (image vs video/audio).
  const contextsFor = {};
  for (const ext of TARGETS.image) (contextsFor[ext] ||= new Set()).add("image");
  for (const ext of TARGETS.video) { (contextsFor[ext] ||= new Set()).add("video"); contextsFor[ext].add("link"); }
  for (const ext of TARGETS.audio) { (contextsFor[ext] ||= new Set()).add("audio"); contextsFor[ext].add("video"); contextsFor[ext].add("link"); }
  for (const [ext, contexts] of Object.entries(contextsFor)) {
    const props = { id: "fc-to-" + ext, parentId: "fc-root", title: t("menuAs", { f: LABELS[ext] }), contexts: [...contexts] };
    if (contexts.has("link")) props.targetUrlPatterns = MEDIA_LINK;
    chrome.contextMenus.create(props);
  }
}

chrome.runtime.onInstalled.addListener(buildMenus);
chrome.runtime.onStartup.addListener(buildMenus);
chrome.storage.onChanged.addListener((changes) => { if (changes.lang) buildMenus(); });

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const url = info.srcUrl || info.linkUrl;
  if (!url) return;
  const kind = info.mediaType || (/\.(mp3|wav|ogg|flac|m4a)(\?|$)/i.test(url) ? "audio" : /\.(jpe?g|png|webp|gif)(\?|$)/i.test(url) ? "image" : "video");
  const page = info.pageUrl || tab?.url || "";
  const blocked = isUnfetchable(url) || (kind !== "image" && isProtectedHost(page));
  if (info.menuItemId === "fc-download" && !blocked) {
    chrome.downloads.download({ url, saveAs: false });
    return;
  }
  const to = String(info.menuItemId).startsWith("fc-to-") ? String(info.menuItemId).slice(6) : "";
  openConverter([{ url, kind, to, blocked }], tab);
});

/** Opens converter.html with a job list. */
function openConverter(jobs, tab) {
  const params = new URLSearchParams({ jobs: JSON.stringify(jobs) });
  chrome.tabs.create({ url: chrome.runtime.getURL("converter.html?" + params), index: tab ? tab.index + 1 : undefined, openerTabId: tab?.id });
}
