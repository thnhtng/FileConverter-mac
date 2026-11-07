// Tiny i18n for extension pages: Vietnamese, Korean, English.
const STR = {
  vi: {
    title: "File Converter", subtitle: "Tải & chuyển đổi media trên trang này",
    all: "Tất cả", images: "Ảnh", videos: "Video", audio: "Âm thanh",
    scanning: "Đang tìm media trên trang…", none: "Không tìm thấy ảnh, video hay âm thanh nào trên trang này.",
    cantScan: "Không đọc được trang này (trang hệ thống hoặc cửa hàng extension).",
    download: "Tải", convertTo: "Chuyển sang…", selected: "{n} đã chọn", downloadSelected: "Tải mục đã chọn", convertSelected: "Chuyển mục đã chọn sang",
    selectAll: "Chọn tất cả", protectedItem: "Stream được bảo vệ — không tải được",
    protectedPage: "Trang này phát video qua stream có bảo vệ (ví dụ YouTube). Theo điều khoản của trang và chính sách Chrome Web Store, extension không tải video ở đây — ảnh vẫn tải được.",
    openConverter: "Chuyển file trên máy…", lang: "Ngôn ngữ",
    jobTitle: "Đang tải & chuyển đổi", fetching: "Đang tải về… {p}", converting: "Đang chuyển… {p}%", loadingEngine: "Đang tải engine video (~31 MB, chỉ lần đầu)…",
    saved: "Đã lưu: {name}", failed: "Lỗi: {msg}", blocked: "Không hỗ trợ: stream được bảo vệ hoặc trang không cho phép tải.",
    allDone: "Xong {ok}/{n} file. Bạn có thể đóng tab này.", privacy: "Mọi thứ chạy ngay trong trình duyệt của bạn — không có file nào bị gửi lên server.",
    menuRoot: "File Converter", menuDownload: "Tải file gốc", menuAs: "Tải & chuyển sang {f}",
  },
  ko: {
    title: "File Converter", subtitle: "이 페이지의 미디어 다운로드 · 변환",
    all: "전체", images: "이미지", videos: "영상", audio: "오디오",
    scanning: "페이지에서 미디어를 찾는 중…", none: "이 페이지에서 이미지, 영상, 오디오를 찾지 못했습니다.",
    cantScan: "이 페이지는 읽을 수 없습니다 (시스템 페이지 또는 확장 프로그램 스토어).",
    download: "다운로드", convertTo: "변환…", selected: "{n}개 선택", downloadSelected: "선택 항목 다운로드", convertSelected: "선택 항목 변환",
    selectAll: "모두 선택", protectedItem: "보호된 스트림 — 다운로드 불가",
    protectedPage: "이 페이지는 보호된 스트리밍으로 영상을 재생합니다(예: YouTube). 해당 사이트 약관과 Chrome 웹 스토어 정책에 따라 영상은 다운로드하지 않으며, 이미지는 받을 수 있습니다.",
    openConverter: "내 파일 변환…", lang: "언어",
    jobTitle: "다운로드 및 변환 중", fetching: "다운로드 중… {p}", converting: "변환 중… {p}%", loadingEngine: "영상 엔진 다운로드 중 (~31 MB, 최초 1회)…",
    saved: "저장됨: {name}", failed: "오류: {msg}", blocked: "지원하지 않음: 보호된 스트림이거나 다운로드가 허용되지 않는 페이지입니다.",
    allDone: "{n}개 중 {ok}개 완료. 이 탭을 닫아도 됩니다.", privacy: "모든 처리는 브라우저 안에서 이루어지며 파일은 서버로 전송되지 않습니다.",
    menuRoot: "File Converter", menuDownload: "원본 다운로드", menuAs: "{f}(으)로 다운로드",
  },
  en: {
    title: "File Converter", subtitle: "Download & convert media on this page",
    all: "All", images: "Images", videos: "Videos", audio: "Audio",
    scanning: "Looking for media on this page…", none: "No images, videos or audio found on this page.",
    cantScan: "This page can't be read (browser or extension-store page).",
    download: "Download", convertTo: "Convert to…", selected: "{n} selected", downloadSelected: "Download selected", convertSelected: "Convert selected to",
    selectAll: "Select all", protectedItem: "Protected stream — can't be downloaded",
    protectedPage: "This page plays video as a protected stream (e.g. YouTube). Per the site's terms and Chrome Web Store policy, the extension doesn't download video here — images still work.",
    openConverter: "Convert files on my computer…", lang: "Language",
    jobTitle: "Downloading & converting", fetching: "Downloading… {p}", converting: "Converting… {p}%", loadingEngine: "Loading the video engine (~31 MB, first time only)…",
    saved: "Saved: {name}", failed: "Error: {msg}", blocked: "Not supported: protected stream or the page doesn't allow downloading.",
    allDone: "Finished {ok} of {n}. You can close this tab.", privacy: "Everything runs in your browser — no file is sent to any server.",
    menuRoot: "File Converter", menuDownload: "Download original", menuAs: "Download as {f}",
  },
};

export async function getLang() {
  try {
    const { lang } = await chrome.storage.local.get("lang");
    if (lang && STR[lang]) return lang;
  } catch (e) { /* storage unavailable */ }
  const n = (navigator.language || "en").slice(0, 2);
  return STR[n] ? n : "en";
}

export async function setLang(lang) {
  await chrome.storage.local.set({ lang });
}

export function makeT(lang) {
  return (k, p) => {
    let s = STR[lang]?.[k] ?? STR.en[k] ?? k;
    if (p) for (const key in p) s = s.split("{" + key + "}").join(p[key]);
    return s;
  };
}

export const LANGS = [["vi", "VI"], ["ko", "한국어"], ["en", "EN"]];
