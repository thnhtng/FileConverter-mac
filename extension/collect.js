// Injected into the page by the popup (chrome.scripting.executeScript).
// Must be self-contained: it's serialized and run in the page's isolated world.
export function collectMedia() {
  const found = new Map();
  const abs = (u) => { try { return new URL(u, document.baseURI).href; } catch (e) { return null; } };
  const add = (raw, kind, extra) => {
    const url = abs(raw);
    if (!url || url === location.href) return;
    if (url.startsWith("data:") && (url.length < 200 || url.length > 3_000_000)) return; // skip spacers / huge inlines
    const prev = found.get(url);
    if (prev) { if (extra && extra.w && !prev.w) Object.assign(prev, extra); return; }
    found.set(url, { url, kind, ...(extra || {}) });
  };
  const largestFromSrcset = (srcset) => {
    let best = null, bestW = -1;
    for (const part of srcset.split(",")) {
      const [u, d] = part.trim().split(/\s+/);
      if (!u) continue;
      const w = d ? parseFloat(d) * (d.endsWith("x") ? 1000 : 1) : 0;
      if (w > bestW) { best = u; bestW = w; }
    }
    return best;
  };

  for (const img of document.images) {
    const src = img.currentSrc || img.src;
    if (img.naturalWidth && img.naturalWidth < 24 && img.naturalHeight < 24) continue; // icons/trackers
    if (src) add(src, "image", { w: img.naturalWidth, h: img.naturalHeight, alt: img.alt || "" });
    if (img.srcset) { const big = largestFromSrcset(img.srcset); if (big) add(big, "image", { alt: img.alt || "" }); }
  }
  for (const s of document.querySelectorAll("picture source[srcset]")) {
    const big = largestFromSrcset(s.srcset); if (big) add(big, "image");
  }
  for (const m of document.querySelectorAll("video, audio")) {
    const kind = m.tagName === "VIDEO" ? "video" : "audio";
    const srcs = [m.currentSrc, m.src, ...[...m.querySelectorAll("source")].map((s) => s.src)].filter(Boolean);
    for (const s of srcs) add(s, kind, kind === "video" ? { w: m.videoWidth || 0, h: m.videoHeight || 0, duration: isFinite(m.duration) ? m.duration : 0 } : { duration: isFinite(m.duration) ? m.duration : 0 });
    if (m.poster) add(m.poster, "image");
  }
  const mediaExt = /\.(mp4|m4v|webm|mov|mkv|mp3|m4a|wav|ogg|oga|flac|aac|jpe?g|png|webp|gif|avif|bmp)(?:[?#]|$)/i;
  for (const a of document.querySelectorAll("a[href]")) {
    const m = mediaExt.exec(a.href);
    if (!m) continue;
    const ext = m[1].toLowerCase();
    add(a.href, /mp4|m4v|webm|mov|mkv/.test(ext) ? "video" : /mp3|m4a|wav|ogg|oga|flac|aac/.test(ext) ? "audio" : "image");
  }
  for (const sel of ['meta[property="og:image"]', 'meta[name="twitter:image"]', 'meta[property="og:image:url"]']) {
    const m = document.querySelector(sel); if (m?.content) add(m.content, "image");
  }
  for (const sel of ['meta[property="og:video"]', 'meta[property="og:video:url"]', 'meta[property="og:video:secure_url"]']) {
    const m = document.querySelector(sel); if (m?.content) add(m.content, "video");
  }
  // CSS background images (bounded so huge pages stay fast).
  const els = document.querySelectorAll("body *");
  for (let i = 0; i < els.length && i < 4000; i++) {
    const bg = getComputedStyle(els[i]).backgroundImage;
    if (!bg || bg === "none") continue;
    for (const m of bg.matchAll(/url\((['"]?)(.*?)\1\)/g)) {
      const r = els[i].getBoundingClientRect();
      if (r.width < 40 && r.height < 40) continue;
      add(m[2], "image", { w: Math.round(r.width), h: Math.round(r.height), css: true });
    }
  }
  return { page: location.href, title: document.title, items: [...found.values()].slice(0, 400) };
}
