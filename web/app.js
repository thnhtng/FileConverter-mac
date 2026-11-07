import {
  loadFormats, categoryOf, targetsFor, extensionOf, convert, saveBlob, formatBytes, preloadFFmpeg, isFFmpegLoaded,
} from "./engine.js";

/* ------------------------------------------------------------------ i18n */
const STR = {
  vi: {
    navConvert: "Chuyển đổi", navEverywhere: "Dùng ở mọi nơi", navFormats: "Định dạng",
    h1: "Chuyển đổi video, âm thanh, ảnh — ngay trong trình duyệt",
    sub: "Thả file vào, chọn đuôi muốn ra, tải về. File không bị tải lên server nào: mọi thứ chạy ngay trên máy bạn.",
    chipPrivate: "Không upload, riêng tư", chipFast: "Ảnh xong tức thì", chipEverywhere: "Có extension & menu chuột phải",
    dropTitle: "Kéo thả file vào đây", dropSub: "Video, âm thanh, ảnh — chọn được nhiều file", choose: "Chọn file",
    allTo: "Chuyển tất cả sang", convertAll: "Chuyển đổi tất cả", downloadAll: "Tải tất cả", clear: "Xóa danh sách",
    convert: "Chuyển", download: "Tải về", remove: "Bỏ", to: "sang",
    ready: "Sẵn sàng", queued: "Đang chờ…", converting: "Đang chuyển… {p}%", loadingEngine: "Đang tải engine video (~31 MB, chỉ lần đầu)…",
    done: "Xong · {size}", unsupported: "Trình duyệt chưa chuyển được loại file này — hãy dùng app trên Mac/Windows.",
    engineIdle: "Engine video: tải khi cần", engineLoading: "Engine video: đang tải…", engineReady: "Engine video: sẵn sàng",
    fine: "Ảnh được chuyển bằng trình duyệt nên gần như tức thì. Video/âm thanh/GIF dùng ffmpeg chạy bằng WebAssembly: chậm hơn app trên máy, phù hợp file vài trăm MB trở xuống. Office → PDF, HEIC/RAW, AVIF và PDF chỉ có trong app.",
    mixed: "(chọn riêng từng file)", toastCopied: "Đã sao chép lệnh", toastNothing: "Chưa có file nào chuyển xong",
    evTitle: "Dùng ở mọi nơi", evLede: "Cùng một bộ định dạng và chất lượng mặc định ở trên web, trong trình duyệt và ngay trong menu chuột phải của máy.",
    extTitle: "Extension trình duyệt", extBody: "Tải ảnh và video có trên trang bạn đang xem, và chuyển đuôi ngay khi tải.",
    ext1: "Chuột phải vào ảnh/video → Tải & chuyển sang MP4, GIF, MP3, JPG, PNG, WEBP…", ext2: "Popup liệt kê mọi ảnh/video của trang, tải một hoặc nhiều", ext3: "Chrome, Edge, Brave, Arc, Opera; Safari qua Xcode",
    extDownload: "Tải extension (.zip)", extNote: "Chỉ tải media có file thật trên trang. Không hỗ trợ YouTube và các trang stream có bảo vệ (theo điều khoản của họ và chính sách Chrome Web Store).",
    macTitle: "Mac — chuột phải trong Finder", macBody: "Chuột phải vào file → Quick Actions → \"Convert to MP4 / MP3 / JPG…\" — chỉ hiện đuôi hợp với file. Có thêm app và Spec Check.",
    macNote: "Dán vào Terminal. Cài Homebrew, ffmpeg, ImageMagick và app.",
    winTitle: "Windows — chuột phải trong Explorer", winBody: "Chuột phải vào file → \"Convert with File Converter\" → chọn đuôi. Không cần quyền admin.",
    winNote: "Dán vào PowerShell. Cài ffmpeg + ImageMagick qua winget. Windows 11: nằm trong \"Show more options\".",
    copy: "Sao chép",
    fmtTitle: "Định dạng hỗ trợ", fmtLede: "Từ loại file nào ra được đuôi nào. Đuôi màu xám chỉ có trong app trên máy.",
    thFrom: "File vào", thTo: "Chuyển được sang", thExamples: "Ví dụ đuôi vào",
    cat_video: "Video", cat_audio: "Âm thanh", cat_image: "Ảnh", cat_animatedImage: "Ảnh động (GIF)", cat_document: "Tài liệu",
    footer: "File Converter · mã nguồn mở GPL-3.0 · dựa trên FileConverter (Windows) của Tichau. File của bạn không rời khỏi máy.",
  },
  ko: {
    navConvert: "변환", navEverywhere: "어디서나 사용", navFormats: "지원 형식",
    h1: "영상·오디오·이미지 변환 — 브라우저에서 바로",
    sub: "파일을 놓고 원하는 확장자를 고른 뒤 내려받으세요. 서버로 업로드하지 않고 모두 내 컴퓨터에서 처리합니다.",
    chipPrivate: "업로드 없음 · 안전", chipFast: "이미지는 즉시 변환", chipEverywhere: "확장 프로그램 · 우클릭 메뉴 제공",
    dropTitle: "여기에 파일을 끌어다 놓으세요", dropSub: "영상, 오디오, 이미지 — 여러 개 선택 가능", choose: "파일 선택",
    allTo: "모두 변환할 형식", convertAll: "모두 변환", downloadAll: "모두 다운로드", clear: "목록 비우기",
    convert: "변환", download: "다운로드", remove: "제거", to: "→",
    ready: "준비됨", queued: "대기 중…", converting: "변환 중… {p}%", loadingEngine: "영상 엔진 다운로드 중 (~31 MB, 최초 1회)…",
    done: "완료 · {size}", unsupported: "이 파일은 브라우저에서 변환할 수 없습니다. Mac/Windows 앱을 사용하세요.",
    engineIdle: "영상 엔진: 필요할 때 로드", engineLoading: "영상 엔진: 로드 중…", engineReady: "영상 엔진: 준비됨",
    fine: "이미지는 브라우저 기능으로 변환해 거의 즉시 끝납니다. 영상·오디오·GIF는 WebAssembly ffmpeg를 사용해 앱보다 느리며, 수백 MB 이하 파일에 적합합니다. Office → PDF, HEIC/RAW, AVIF, PDF는 앱에서만 지원합니다.",
    mixed: "(파일별로 선택)", toastCopied: "명령어를 복사했습니다", toastNothing: "아직 변환된 파일이 없습니다",
    evTitle: "어디서나 사용", evLede: "웹, 브라우저, 그리고 컴퓨터의 우클릭 메뉴에서 같은 형식과 같은 기본 품질로 변환합니다.",
    extTitle: "브라우저 확장 프로그램", extBody: "보고 있는 페이지의 이미지와 영상을 내려받으면서 바로 원하는 형식으로 변환합니다.",
    ext1: "이미지/영상 우클릭 → 다운로드 후 MP4, GIF, MP3, JPG, PNG, WEBP… 로 변환", ext2: "팝업에서 페이지의 모든 이미지·영상을 보고 하나 또는 여러 개 다운로드", ext3: "Chrome, Edge, Brave, Arc, Opera · Safari는 Xcode로 변환",
    extDownload: "확장 프로그램 받기 (.zip)", extNote: "페이지에 실제 파일로 있는 미디어만 다운로드합니다. YouTube 등 보호된 스트리밍 사이트는 각 서비스 약관과 Chrome 웹 스토어 정책에 따라 지원하지 않습니다.",
    macTitle: "Mac — Finder 우클릭", macBody: "파일 우클릭 → 빠른 동작 → \"Convert to MP4 / MP3 / JPG…\" — 파일에 맞는 형식만 표시됩니다. 앱과 Spec Check도 함께 설치됩니다.",
    macNote: "터미널에 붙여 넣으세요. Homebrew, ffmpeg, ImageMagick과 앱을 설치합니다.",
    winTitle: "Windows — 탐색기 우클릭", winBody: "파일 우클릭 → \"Convert with File Converter\" → 형식 선택. 관리자 권한이 필요 없습니다.",
    winNote: "PowerShell에 붙여 넣으세요. winget으로 ffmpeg와 ImageMagick을 설치합니다. Windows 11은 \"추가 옵션 표시\" 안에 있습니다.",
    copy: "복사",
    fmtTitle: "지원 형식", fmtLede: "어떤 파일을 어떤 형식으로 바꿀 수 있는지 정리했습니다. 회색 형식은 데스크톱 앱에서만 지원합니다.",
    thFrom: "입력 파일", thTo: "변환 가능한 형식", thExamples: "입력 확장자 예",
    cat_video: "영상", cat_audio: "오디오", cat_image: "이미지", cat_animatedImage: "움직이는 이미지 (GIF)", cat_document: "문서",
    footer: "File Converter · GPL-3.0 오픈소스 · Tichau의 FileConverter(Windows) 기반. 파일은 내 컴퓨터를 벗어나지 않습니다.",
  },
  en: {
    navConvert: "Convert", navEverywhere: "Use it everywhere", navFormats: "Formats",
    h1: "Convert video, audio and images — right in your browser",
    sub: "Drop files, pick the format you want, download. Nothing is uploaded to any server: everything runs on your own machine.",
    chipPrivate: "No uploads, private", chipFast: "Images convert instantly", chipEverywhere: "Extension & right-click menu",
    dropTitle: "Drop files here", dropSub: "Video, audio, images — several at once", choose: "Choose files",
    allTo: "Convert all to", convertAll: "Convert all", downloadAll: "Download all", clear: "Clear",
    convert: "Convert", download: "Download", remove: "Remove", to: "to",
    ready: "Ready", queued: "Queued…", converting: "Converting… {p}%", loadingEngine: "Loading the video engine (~31 MB, first time only)…",
    done: "Done · {size}", unsupported: "Your browser can't convert this type — use the Mac/Windows app.",
    engineIdle: "Video engine: loads when needed", engineLoading: "Video engine: loading…", engineReady: "Video engine: ready",
    fine: "Images are converted by the browser itself, so they're near-instant. Video, audio and GIF use ffmpeg compiled to WebAssembly: slower than the desktop app, best for files up to a few hundred MB. Office → PDF, HEIC/RAW, AVIF and PDF are desktop-only.",
    mixed: "(choose per file)", toastCopied: "Command copied", toastNothing: "No converted files yet",
    evTitle: "Use it everywhere", evLede: "The same formats and default quality on the web, in your browser, and right in your computer's right-click menu.",
    extTitle: "Browser extension", extBody: "Download the images and videos on the page you're viewing, converting them as they download.",
    ext1: "Right-click an image/video → Download as MP4, GIF, MP3, JPG, PNG, WEBP…", ext2: "Popup lists every image and video on the page; grab one or many", ext3: "Chrome, Edge, Brave, Arc, Opera; Safari via Xcode",
    extDownload: "Get the extension (.zip)", extNote: "Downloads media that exists as real files on the page. YouTube and other protected streaming sites aren't supported (their terms and Chrome Web Store policy).",
    macTitle: "Mac — right-click in Finder", macBody: "Right-click a file → Quick Actions → \"Convert to MP4 / MP3 / JPG…\" — only formats that fit the file appear. Includes the app and Spec Check.",
    macNote: "Paste into Terminal. Installs Homebrew, ffmpeg, ImageMagick and the app.",
    winTitle: "Windows — right-click in Explorer", winBody: "Right-click a file → \"Convert with File Converter\" → pick a format. No admin rights needed.",
    winNote: "Paste into PowerShell. Installs ffmpeg + ImageMagick via winget. On Windows 11 it's under \"Show more options\".",
    copy: "Copy",
    fmtTitle: "Supported formats", fmtLede: "Which file types convert to which formats. Grey formats are desktop-app only.",
    thFrom: "Input", thTo: "Converts to", thExamples: "Example input extensions",
    cat_video: "Video", cat_audio: "Audio", cat_image: "Image", cat_animatedImage: "Animated image (GIF)", cat_document: "Document",
    footer: "File Converter · GPL-3.0 open source · based on Tichau's FileConverter (Windows). Your files never leave your machine.",
  },
};

let lang = (() => {
  try { const s = localStorage.getItem("fc-lang"); if (s && STR[s]) return s; } catch (e) { /* storage blocked */ }
  const n = (navigator.language || "vi").slice(0, 2);
  return STR[n] ? n : "vi";
})();
const t = (k, p) => {
  let s = STR[lang][k] ?? STR.en[k] ?? k;
  if (p) for (const key in p) s = s.split("{" + key + "}").join(p[key]);
  return s;
};
const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

/* ------------------------------------------------------------------ state */
const state = { items: [], engine: "idle" };
let formats = null;
let uid = 0;
const $ = (id) => document.getElementById(id);

const ICONS = { video: "🎬", audio: "🎵", image: "🖼", animatedImage: "🖼", document: "📄" };

function defaultTarget(item) {
  const targets = targetsFor(formats, item.category);
  const ext = extensionOf(item.name);
  const prefs = { video: ["mp4", "webm"], audio: ["mp3", "wav"], image: ext === "png" ? ["jpg"] : ["png", "jpg"], animatedImage: ["mp4", "webm"] }[item.category] || [];
  for (const p of prefs) if (p !== ext && targets.some((x) => x.ext === p)) return p;
  return (targets.find((x) => x.ext !== ext) || targets[0] || {}).ext || null;
}

function addFiles(fileList) {
  for (const file of fileList) {
    const category = categoryOf(formats, file.name, file.type);
    const item = { id: ++uid, file, name: file.name, size: file.size, category, status: "ready", progress: 0, result: null, error: null, thumb: null };
    item.target = defaultTarget(item);
    if (!item.target) { item.status = "error"; item.error = t("unsupported"); }
    if (category === "image" || category === "animatedImage") item.thumb = URL.createObjectURL(file);
    state.items.push(item);
    if (["video", "audio", "animatedImage"].includes(category) && !isFFmpegLoaded()) warmEngine();
  }
  render();
}

function warmEngine() {
  state.engine = "loading"; renderEngine();
  preloadFFmpeg().then((ok) => { state.engine = ok ? "ready" : "idle"; renderEngine(); });
}

async function convertItem(item) {
  if (!item.target || item.status === "converting") return;
  item.status = "converting"; item.progress = 0; item.error = null; item.result = null; item.stage = null;
  renderItem(item);
  try {
    item.result = await convert(item.file, item.name, item.target, {
      onProgress: (p) => { item.progress = p; item.stage = "run"; updateProgress(item); },
      onStage: (s) => { item.stage = s; if (s === "engine" && !isFFmpegLoaded()) { state.engine = "loading"; renderEngine(); } renderItem(item); },
    });
    item.status = "done";
    if (isFFmpegLoaded()) state.engine = "ready";
  } catch (e) {
    item.status = "error";
    item.error = String(e && e.message ? e.message : e).slice(0, 220);
  }
  renderItem(item); renderToolbar(); renderEngine();
}

async function convertAll() {
  const pending = state.items.filter((i) => i.target && (i.status === "ready" || i.status === "error"));
  pending.forEach((i) => { i.status = "queued"; renderItem(i); });
  // Images (canvas) are quick and independent; ffmpeg jobs serialize inside the engine.
  await Promise.all(pending.map((i) => { i.status = "ready"; return convertItem(i); }));
}

function downloadAll() {
  const done = state.items.filter((i) => i.result);
  if (!done.length) return toast(t("toastNothing"));
  done.forEach((i, n) => setTimeout(() => saveBlob(i.result.blob, i.result.name), n * 350));
}

/* ------------------------------------------------------------------ render */
function render() {
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll("[data-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
  $("files").innerHTML = state.items.map(itemHTML).join("");
  renderToolbar(); renderEngine(); renderFormats();
}

function itemHTML(item) {
  const targets = targetsFor(formats, item.category);
  const thumb = item.thumb ? `<img src="${item.thumb}" alt="">` : (ICONS[item.category] || "📄");
  const busy = item.status === "converting" || item.status === "queued";
  const select = targets.length
    ? `<label class="target"><span>${esc(t("to"))}</span><select data-target="${item.id}" ${busy ? "disabled" : ""}>${targets.map((x) => `<option value="${x.ext}" ${x.ext === item.target ? "selected" : ""}>${x.label}</option>`).join("")}</select></label>`
    : `<span></span>`;
  let action;
  if (item.status === "done") action = `<button type="button" class="btn primary small" data-download="${item.id}">${esc(t("download"))}</button>`;
  else action = `<button type="button" class="btn small" data-convert="${item.id}" ${!item.target || busy ? "disabled" : ""}>${esc(t("convert"))}</button>`;
  return `<li class="file" id="item-${item.id}">
    <div class="thumb">${thumb}</div>
    <div><div class="fname" title="${esc(item.name)}">${esc(item.name)}</div><div class="fmeta">${metaHTML(item)}</div>${item.status === "converting" ? `<div class="bar"><i id="bar-${item.id}" style="width:${Math.round(item.progress * 100)}%"></i></div>` : ""}</div>
    ${select}
    <div class="actions">${action}<button type="button" class="icon-btn" data-remove="${item.id}" aria-label="${esc(t("remove"))}" title="${esc(t("remove"))}" ${busy ? "disabled" : ""}>✕</button></div>
  </li>`;
}

function metaHTML(item) {
  const base = `${formatBytes(item.size)}${item.category ? " · " + esc(t("cat_" + item.category)) : ""}`;
  switch (item.status) {
    case "queued": return base + " · " + esc(t("queued"));
    case "converting":
      if (item.stage === "engine" && !isFFmpegLoaded()) return base + " · " + esc(t("loadingEngine"));
      return base + " · " + esc(t("converting", { p: Math.round(item.progress * 100) }));
    case "done": return base + ` · <span class="ok">✓ ${esc(t("done", { size: formatBytes(item.result.blob.size) }))}</span> → ${esc(item.result.name)}`;
    case "error": return base + ` · <span class="err">${esc(item.error)}</span>`;
    default: return base;
  }
}

function renderItem(item) {
  const el = $("item-" + item.id);
  if (!el) return render();
  el.outerHTML = itemHTML(item);
}

function updateProgress(item) {
  const bar = $("bar-" + item.id);
  if (!bar) return renderItem(item);
  bar.style.width = Math.round(item.progress * 100) + "%";
  const meta = bar.parentElement.parentElement.querySelector(".fmeta");
  if (meta) meta.innerHTML = metaHTML(item);
}

function renderToolbar() {
  $("toolbar").hidden = state.items.length === 0;
  const cats = [...new Set(state.items.map((i) => i.category).filter(Boolean))];
  const common = cats.length ? targetsFor(formats, cats[0]).filter((x) => cats.every((c) => targetsFor(formats, c).some((y) => y.ext === x.ext))) : [];
  const targetsInUse = new Set(state.items.map((i) => i.target));
  const current = targetsInUse.size === 1 ? [...targetsInUse][0] : "";
  $("all-target").innerHTML = `<option value="">${esc(t("mixed"))}</option>` + common.map((x) => `<option value="${x.ext}" ${x.ext === current ? "selected" : ""}>${x.label}</option>`).join("");
  $("all-target").disabled = !common.length;
  $("download-all").disabled = !state.items.some((i) => i.result);
  $("convert-all").disabled = !state.items.some((i) => i.target && (i.status === "ready" || i.status === "error"));
}

function renderEngine() {
  const needed = state.items.some((i) => ["video", "audio", "animatedImage"].includes(i.category));
  $("engine-status").textContent = needed || state.engine !== "idle" ? t({ idle: "engineIdle", loading: "engineLoading", ready: "engineReady" }[state.engine]) : "";
}

function renderFormats() {
  const order = ["video", "audio", "image", "animatedImage", "document"];
  const rows = order.map((cat) => {
    const all = Object.entries(formats.outputs).filter(([, o]) => o.accepts.includes(cat));
    const pills = all.map(([ext, o]) => `<span class="pill ${o.web === false || cat === "document" ? "app" : ""}">${o.label}</span>`).join("");
    const examples = formats.categories[cat].slice(0, 12).map((e) => "." + e).join(" ");
    return `<tr><th scope="row">${esc(t("cat_" + cat))}</th><td>${pills}</td><td class="exts">${examples}</td></tr>`;
  });
  $("fmt-table").innerHTML = `<tr><th>${esc(t("thFrom"))}</th><th>${esc(t("thTo"))}</th><th>${esc(t("thExamples"))}</th></tr>` + rows.join("");
}

let toastTimer;
function toast(msg) {
  const el = $("toast");
  el.textContent = msg; el.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, 2400);
}

/* ------------------------------------------------------------------ events */
function bind() {
  const input = $("file-input");
  input.addEventListener("change", () => { addFiles(input.files); input.value = ""; });
  const drop = $("drop");
  let depth = 0;
  document.addEventListener("dragenter", (e) => { if (e.dataTransfer?.types?.includes("Files")) { depth++; drop.classList.add("drag"); } });
  document.addEventListener("dragleave", () => { if (--depth <= 0) { depth = 0; drop.classList.remove("drag"); } });
  document.addEventListener("dragover", (e) => e.preventDefault());
  document.addEventListener("drop", (e) => {
    e.preventDefault(); depth = 0; drop.classList.remove("drag");
    if (e.dataTransfer?.files?.length) addFiles(e.dataTransfer.files);
  });
  document.addEventListener("paste", (e) => { const files = [...(e.clipboardData?.files || [])]; if (files.length) addFiles(files); });

  document.addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b) return;
    const d = b.dataset;
    if (d.lang) { lang = d.lang; try { localStorage.setItem("fc-lang", lang); } catch (err) { /* ignore */ } render(); return; }
    const item = (id) => state.items.find((i) => i.id === +id);
    if (d.convert) return convertItem(item(d.convert));
    if (d.download) { const it = item(d.download); if (it?.result) saveBlob(it.result.blob, it.result.name); return; }
    if (d.remove) {
      const it = item(d.remove); if (it?.thumb) URL.revokeObjectURL(it.thumb);
      state.items = state.items.filter((i) => i.id !== +d.remove); render(); return;
    }
    if (d.copy) { navigator.clipboard?.writeText($(d.copy).textContent).then(() => toast(t("toastCopied")), () => {}); return; }
    if (b.id === "convert-all") return convertAll();
    if (b.id === "download-all") return downloadAll();
    if (b.id === "clear") {
      state.items.filter((i) => i.status !== "converting").forEach((i) => i.thumb && URL.revokeObjectURL(i.thumb));
      state.items = state.items.filter((i) => i.status === "converting"); render();
    }
  });
  document.addEventListener("change", (e) => {
    const el = e.target;
    if (el.dataset.target) {
      const it = state.items.find((i) => i.id === +el.dataset.target);
      if (it) { it.target = el.value; if (it.status === "done" || it.status === "error") { it.status = "ready"; it.result = null; it.error = null; } renderItem(it); renderToolbar(); }
    }
    if (el.id === "all-target" && el.value) {
      state.items.forEach((i) => {
        if (i.status === "converting" || i.status === "queued") return;
        if (targetsFor(formats, i.category).some((x) => x.ext === el.value)) { i.target = el.value; if (i.status !== "ready") { i.status = "ready"; i.result = null; i.error = null; } }
      });
      render();
    }
  });
}

formats = await loadFormats();
bind();
render();
