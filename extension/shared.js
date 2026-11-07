// Helpers shared by the popup, the converter page and the background worker.

/** Hosts whose video is streamed with protection (MSE/DRM). We don't try to
 *  download from these — their terms forbid it and the Chrome Web Store
 *  rejects extensions that do. Images on these sites still work. */
export const PROTECTED_VIDEO_HOSTS = [
  "youtube.com", "youtu.be", "youtube-nocookie.com", "netflix.com", "disneyplus.com", "primevideo.com",
  "hulu.com", "max.com", "hbomax.com", "spotify.com", "music.apple.com", "tv.apple.com", "twitch.tv",
];

export function isProtectedHost(pageUrl) {
  try {
    const host = new URL(pageUrl).hostname.replace(/^www\./, "");
    return PROTECTED_VIDEO_HOSTS.some((h) => host === h || host.endsWith("." + h));
  } catch (e) {
    return false;
  }
}

/** Streams the extension can't fetch as a file. */
export function isUnfetchable(url) {
  return /^(blob:|mediastream:|mediasource:)/i.test(url || "");
}

/** Best file name for a media URL: last path segment, sanitized, with an extension. */
export function fileNameFromUrl(url, kind, contentType = "") {
  let name = "";
  try {
    const u = new URL(url);
    if (u.protocol === "data:") name = "";
    else name = decodeURIComponent(u.pathname.split("/").filter(Boolean).pop() || "");
  } catch (e) { /* keep empty */ }
  name = name.replace(/[\\/:*?"<>|\u0000-\u001f]+/g, "_").slice(0, 120);
  const hasExt = /\.[a-z0-9]{2,5}$/i.test(name);
  if (!hasExt) {
    const ext = extFromType(contentType) || ({ image: "jpg", video: "mp4", audio: "mp3" })[kind] || "bin";
    name = (name || kind || "download") + "." + ext;
  }
  return name;
}

export function extFromType(type) {
  const t = (type || "").split(";")[0].trim().toLowerCase();
  return ({
    "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/avif": "avif",
    "image/svg+xml": "svg", "image/bmp": "bmp", "image/x-icon": "ico", "image/vnd.microsoft.icon": "ico",
    "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "video/x-matroska": "mkv", "video/ogg": "ogv",
    "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/ogg": "ogg", "audio/wav": "wav", "audio/x-wav": "wav",
    "audio/flac": "flac", "audio/webm": "webm",
  })[t] || "";
}

/** Context-menu / popup target lists per media kind. */
export const TARGETS = {
  image: ["png", "jpg", "webp", "gif", "ico"],
  video: ["mp4", "webm", "gif", "mp3", "wav"],
  audio: ["mp3", "wav", "ogg", "flac", "aac"],
};

export const LABELS = { png: "PNG", jpg: "JPG", webp: "WEBP", gif: "GIF", ico: "ICO", mp4: "MP4", webm: "WEBM", mp3: "MP3", wav: "WAV", ogg: "OGG", flac: "FLAC", aac: "AAC" };
