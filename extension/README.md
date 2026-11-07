# File Converter — browser extension

Download the images, videos and audio on any page and convert them while
downloading (MP4, WEBM, GIF, MP3, WAV, OGG, FLAC, AAC, JPG, PNG, WEBP, ICO).
Conversion runs inside the browser with the same engine and format table
as the web converter (`web/engine.js`, `shared/formats.json`); nothing is
uploaded.

- **Right-click** an image, video, audio element or media link →
  *File Converter* → *Download original* / *Download as …* (only formats
  that fit what you clicked are shown).
- **Toolbar popup** lists every image, video and audio file on the current
  page (img, srcset, picture, video/audio sources, media links, CSS
  backgrounds, og:image/og:video), with filters, multi-select, *Download
  selected* and *Convert selected to …*.
- **Convert files on my computer…** opens the bundled web converter.
- UI in Tiếng Việt / 한국어 / English.

**Not supported, on purpose:** YouTube and other protected streaming sites
(their video is delivered as encrypted/segmented streams, their terms
forbid downloading, and the Chrome Web Store rejects extensions that do
it). Such items are shown as "protected stream" and skipped; images on
those sites still work.

## Build & install

```bash
scripts/build-extension.sh
```

Produces `dist/extension/` and `dist/FileConverter-extension.zip` (the zip
is also published next to the web converter by the Pages workflow).

- **Chrome / Edge / Brave / Arc / Opera:** open `chrome://extensions`
  (`edge://extensions`…), turn on *Developer mode*, *Load unpacked* →
  pick the unzipped folder.
- **Safari (Mac, needs Xcode):**
  `xcrun safari-web-extension-converter dist/extension --app-name "File Converter"`,
  build and run the generated project once, then enable it in Safari →
  Settings → Extensions.
- **Firefox:** not packaged yet (Firefox MV3 needs `background.scripts`
  instead of a service worker).

Permissions: `contextMenus`, `downloads`, `scripting` + `activeTab` (read
the page's media list when you open the popup), `storage` (language),
and access to all sites so media can be fetched for conversion. The CSP
adds `'wasm-unsafe-eval'` for ffmpeg.wasm, which is bundled — no remote
code is loaded.
