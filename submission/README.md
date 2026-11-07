# AX Hero submission — Spec Check

Two self-contained HTML files (no server, no internet needed — double-click to open):

| File | What it is |
|---|---|
| `mockup.html` | Service mockup. Click **Try sample files**, then **Fix all**; open **Manage specs… → Draft from text with AI**; export a report. Real files can be dropped too (read locally for size/length/dimensions only). |
| `intro.html` | Service introduction page: problem, before/after workflow, how it works, theme fit, impact estimator, limits, install. |

Both switch between Tiếng Việt / 한국어 / English (top-right). Sizes: ~80 KB and ~40 KB.

The real implementation lives in this repo: `Packages/FileConverterKit/Sources/FileConverterKit/SpecCheck/` (engine, 93 passing tests) and `FileConverter/Views/Spec*.swift` (macOS UI).
