// File Converter — in-browser conversion engine.
//
// Shared by the web converter (web/index.html) and the browser extension
// (extension/converter.html). Everything runs locally: images go through
// <canvas>, audio/video/GIF through ffmpeg.wasm (single-threaded core, so no
// SharedArrayBuffer / cross-origin-isolation headers are needed).
//
// Output settings come from shared/formats.json, the same table the macOS
// app (FileConverterKit) and the Windows right-click menu use.

/** @typedef {{label:string, kind:string, accepts:string[], ffmpeg?:string[], image?:{mime:string,quality:number,maxSize?:number}, gif?:{fps:number}, web?:boolean}} OutputSpec */

let formatsPromise = null;
let ffmpegPromise = null;
let ffmpegBusy = Promise.resolve();

/** Where vendor/ (ffmpeg) and formats.json live, relative to this module. */
const BASE = new URL("./", import.meta.url);

export function loadFormats(url = new URL("formats.json", BASE)) {
  if (!formatsPromise) {
    formatsPromise = fetch(url).then((r) => {
      if (!r.ok) throw new Error("formats.json: HTTP " + r.status);
      return r.json();
    });
  }
  return formatsPromise;
}

export function extensionOf(name) {
  const m = /\.([a-z0-9]+)$/i.exec(name || "");
  const ext = m ? m[1].toLowerCase() : "";
  return ext === "jpeg" ? "jpg" : ext;
}

export function stemOf(name) {
  return (name || "file").replace(/\.[^./\\]+$/, "") || "file";
}

/** Category of a file: audio | video | image | animatedImage | document | null. */
export function categoryOf(formats, name, mime = "") {
  const ext = extensionOf(name);
  for (const [cat, exts] of Object.entries(formats.categories)) {
    if (exts.includes(ext) || (ext === "jpg" && exts.includes("jpeg"))) return cat;
  }
  if (mime.startsWith("video/")) return "video";
  if (mime.startsWith("audio/")) return "audio";
  if (mime === "image/gif") return "animatedImage";
  if (mime.startsWith("image/")) return "image";
  return null;
}

/** Output formats the browser can produce for a category, in table order. */
export function targetsFor(formats, category) {
  if (!category || category === "document") return [];
  return Object.entries(formats.outputs)
    .filter(([, o]) => o.web !== false && o.accepts.includes(category))
    .map(([ext, o]) => ({ ext, label: o.label, kind: o.kind }));
}

/** Download file name: "clip.mov" -> "clip.mp4"; same extension gets a suffix. */
export function outputName(inputName, ext) {
  const stem = stemOf(inputName);
  return extensionOf(inputName) === ext ? `${stem} (converted).${ext}` : `${stem}.${ext}`;
}

// ---------------------------------------------------------------- ffmpeg.wasm

async function getFFmpeg() {
  if (!ffmpegPromise) {
    ffmpegPromise = (async () => {
      const { FFmpeg } = await import(new URL("vendor/ffmpeg/index.js", BASE).href);
      const ffmpeg = new FFmpeg();
      await ffmpeg.load({
        coreURL: new URL("vendor/core/ffmpeg-core.js", BASE).href,
        wasmURL: new URL("vendor/core/ffmpeg-core.wasm", BASE).href,
      });
      return ffmpeg;
    })();
    ffmpegPromise.catch(() => { ffmpegPromise = null; });
  }
  return ffmpegPromise;
}

/** Starts downloading the ~31 MB engine early (e.g. when the first video is added). */
export function preloadFFmpeg() {
  return getFFmpeg().then(() => true, () => false);
}

export function isFFmpegLoaded() {
  return ffmpegPromise !== null;
}

/** Serializes ffmpeg runs: one wasm instance, one job at a time. */
function exclusive(task) {
  const run = ffmpegBusy.then(task, task);
  ffmpegBusy = run.catch(() => {});
  return run;
}

async function runFFmpeg(input, inputName, buildPasses, outName, onProgress) {
  return exclusive(async () => {
    const ffmpeg = await getFFmpeg();
    const logs = [];
    const onLog = ({ message }) => { logs.push(message); if (logs.length > 40) logs.shift(); };
    const passes = buildPasses();
    let passIndex = 0;
    const onFFProgress = ({ progress }) => {
      if (!onProgress || !(progress >= 0 && progress <= 1)) return;
      onProgress((passIndex + progress) / passes.length);
    };
    ffmpeg.on("log", onLog);
    ffmpeg.on("progress", onFFProgress);
    const created = [inputName];
    try {
      await ffmpeg.writeFile(inputName, new Uint8Array(await input.arrayBuffer()));
      for (; passIndex < passes.length; passIndex++) {
        const { args, output } = passes[passIndex];
        created.push(output);
        const code = await ffmpeg.exec(args);
        if (code !== 0) throw new Error("ffmpeg failed (" + code + "): " + logs.slice(-6).join(" | "));
      }
      const data = await ffmpeg.readFile(outName);
      return data;
    } catch (e) {
      // A wasm trap (e.g. "RuntimeError: ...") leaves the instance unusable:
      // drop it so the next job starts from a fresh one.
      if (/RuntimeError|memory|abort/i.test(String(e && e.message))) {
        try { ffmpeg.terminate(); } catch (err) { /* already gone */ }
        ffmpegPromise = null;
      }
      throw e;
    } finally {
      ffmpeg.off("log", onLog);
      ffmpeg.off("progress", onFFProgress);
      for (const f of created) { try { await ffmpeg.deleteFile(f); } catch (e) { /* not created */ } }
    }
  });
}

// ---------------------------------------------------------------- images

async function decodeImage(blob) {
  try {
    return await createImageBitmap(blob);
  } catch (e) {
    return null; // e.g. TIFF/HEIC/PSD — caller falls back to ffmpeg
  }
}

function canvasToBlob(bitmap, mime, quality, maxSize) {
  let { width, height } = bitmap;
  if (maxSize && Math.max(width, height) > maxSize) {
    const scale = maxSize / Math.max(width, height);
    width = Math.max(1, Math.round(width * scale));
    height = Math.max(1, Math.round(height * scale));
  }
  const canvas = typeof OffscreenCanvas !== "undefined" ? new OffscreenCanvas(width, height) : Object.assign(document.createElement("canvas"), { width, height });
  const ctx = canvas.getContext("2d");
  if (mime === "image/jpeg") { ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, width, height); } // no alpha in JPG
  ctx.drawImage(bitmap, 0, 0, width, height);
  const q = Math.max(0.01, Math.min(1, quality / 100));
  if (canvas.convertToBlob) return canvas.convertToBlob({ type: mime, quality: q });
  return new Promise((res, rej) => canvas.toBlob((b) => (b ? res(b) : rej(new Error("Encoding failed"))), mime, q));
}

/** Wraps one PNG in an .ico container (Vista+ readers accept PNG entries). */
async function pngToIco(pngBlob, width, height) {
  const png = new Uint8Array(await pngBlob.arrayBuffer());
  const header = new ArrayBuffer(6 + 16);
  const v = new DataView(header);
  v.setUint16(0, 0, true); v.setUint16(2, 1, true); v.setUint16(4, 1, true);
  v.setUint8(6, width >= 256 ? 0 : width); v.setUint8(7, height >= 256 ? 0 : height);
  v.setUint8(8, 0); v.setUint8(9, 0); v.setUint16(10, 1, true); v.setUint16(12, 32, true);
  v.setUint32(14, png.length, true); v.setUint32(18, 22, true);
  return new Blob([header, png], { type: "image/x-icon" });
}

function imageMagickLikeFfmpegArgs(spec, ext) {
  // ffmpeg fallback for images the browser can't decode.
  const q = spec.image.quality;
  if (ext === "jpg") return ["-q:v", String(Math.max(2, Math.round(31 - (q / 100) * 29)))];
  if (ext === "webp") return ["-c:v", "libwebp", "-quality", String(q)];
  return [];
}

// ---------------------------------------------------------------- convert

/**
 * Converts a Blob/File to `targetExt`.
 * @param {Blob} input
 * @param {string} inputName original file name (extension used for detection)
 * @param {string} targetExt key of formats.outputs
 * @param {{onProgress?:(f:number)=>void, onStage?:(s:string)=>void}} [opts]
 * @returns {Promise<{blob: Blob, name: string}>}
 */
export async function convert(input, inputName, targetExt, opts = {}) {
  const formats = await loadFormats();
  const spec = formats.outputs[targetExt];
  if (!spec || spec.web === false) throw new Error("Unsupported target: " + targetExt);
  const category = categoryOf(formats, inputName, input.type || "");
  if (!category || !spec.accepts.includes(category)) throw new Error(`Can't convert ${extensionOf(inputName) || "this file"} to ${spec.label}`);
  const name = outputName(inputName, targetExt);
  const onProgress = opts.onProgress || (() => {});
  const stage = opts.onStage || (() => {});
  const inExt = extensionOf(inputName) || "bin";
  const inFile = "in." + inExt;

  // Images: canvas first (fast, no 31 MB download).
  if (spec.image) {
    const bitmap = await decodeImage(input);
    if (bitmap) {
      stage("encoding");
      const pngForIco = targetExt === "ico";
      const blob = await canvasToBlob(bitmap, pngForIco ? "image/png" : spec.image.mime, spec.image.quality, spec.image.maxSize);
      const w = Math.min(bitmap.width, spec.image.maxSize || bitmap.width);
      const h = Math.min(bitmap.height, spec.image.maxSize || bitmap.height);
      bitmap.close?.();
      // Safari can't encode WebP from canvas and silently returns PNG.
      if (pngForIco || blob.type === spec.image.mime) {
        onProgress(1);
        return { blob: pngForIco ? await pngToIco(blob, w, h) : blob, name };
      }
    }
    stage("engine");
    const outFile = "out." + (targetExt === "ico" ? "png" : targetExt);
    const m = spec.image.maxSize;
    const scale = m ? ["-vf", `scale=w='min(${m},iw)':h='min(${m},ih)':force_original_aspect_ratio=decrease`] : [];
    const data = await runFFmpeg(input, inFile, () => [{ args: ["-i", inFile, "-frames:v", "1", ...scale, ...imageMagickLikeFfmpegArgs(spec, targetExt), outFile], output: outFile }], outFile, onProgress);
    const blob = new Blob([data], { type: targetExt === "ico" ? "image/png" : spec.image.mime });
    onProgress(1);
    if (targetExt === "ico") {
      const bm = await decodeImage(blob);
      return { blob: await pngToIco(blob, bm ? bm.width : 256, bm ? bm.height : 256), name };
    }
    return { blob, name };
  }

  // GIF: 2-pass palette pipeline, same as FFmpegArgumentBuilder.swift.
  stage("engine");
  if (spec.gif) {
    const filter = `fps=${spec.gif.fps}`;
    const data = await runFFmpeg(input, inFile, () => [
      { args: ["-i", inFile, "-vf", `${filter},palettegen`, "palette.png"], output: "palette.png" },
      { args: ["-i", inFile, "-i", "palette.png", "-lavfi", `${filter},paletteuse`, "out.gif"], output: "out.gif" },
    ], "out.gif", onProgress);
    onProgress(1);
    return { blob: new Blob([data], { type: "image/gif" }), name };
  }

  const outFile = "out." + targetExt;
  // `webFfmpeg` overrides for codecs that are too heavy for single-threaded wasm.
  const args = [...(spec.webFfmpeg || spec.ffmpeg)];
  const data = await runFFmpeg(input, inFile, () => [{ args: ["-i", inFile, ...args, outFile], output: outFile }], outFile, onProgress);
  onProgress(1);
  return { blob: new Blob([data], { type: mimeFor(targetExt) }), name };
}

export function mimeFor(ext) {
  return ({
    mp4: "video/mp4", mkv: "video/x-matroska", webm: "video/webm", avi: "video/x-msvideo", ogv: "video/ogg",
    gif: "image/gif", mp3: "audio/mpeg", aac: "audio/aac", ogg: "audio/ogg", flac: "audio/flac", wav: "audio/wav",
    jpg: "image/jpeg", png: "image/png", webp: "image/webp", ico: "image/x-icon",
  })[ext] || "application/octet-stream";
}

/** Triggers a browser download of a Blob. */
export function saveBlob(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
}

export function formatBytes(n) {
  if (!(n >= 0)) return "";
  if (n < 1024) return n + " B";
  if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB";
  if (n < 1024 ** 3) return (n / 1024 / 1024).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB";
  return (n / 1024 ** 3).toFixed(2) + " GB";
}
