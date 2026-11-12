/*
 * EHOT OS Monitor WebExtension (Firefox MV3)
 * Privacy rules:
 *  1. webNavigation filter runs strictly on youtube.com / youtu.be only.
 *     Other sites are NEVER inspected, stored, or logged.
 *  2. downloads.onCreated forwards ONLY basename + source hostname.
 *     File contents are NEVER accessed or logged.
 */

const NATIVE_HOST = "com.ehotos.control";
const recentVideos = new Map();
const DEDUP_WINDOW_MS = 120 * 1000;

function extractYouTubeVideoId(rawUrl) {
  try {
    const u = new URL(rawUrl);
    const host = u.hostname.toLowerCase();
    if (host === "youtu.be") {
      const id = u.pathname.replace(/^\/+/, "").split("/")[0];
      return id || null;
    }
    if (host.endsWith("youtube.com")) {
      if (u.pathname === "/watch") {
        return u.searchParams.get("v");
      }
      if (u.pathname.startsWith("/shorts/")) {
        const parts = u.pathname.split("/").filter(Boolean);
        return parts[1] || null;
      }
    }
  } catch (_e) {
    return null;
  }
  return null;
}

function sendNativeEvent(payload) {
  try {
    return browser.runtime.sendNativeMessage(NATIVE_HOST, payload);
  } catch (_err) {
    return Promise.resolve();
  }
}

function handleYouTubeNavigation(details) {
  if (details.frameId !== 0) {
    return;
  }
  const videoId = extractYouTubeVideoId(details.url);
  if (!videoId) {
    return;
  }

  const now = Date.now();
  const prev = recentVideos.get(videoId);
  if (prev && now - prev < DEDUP_WINDOW_MS) {
    return;
  }
  recentVideos.set(videoId, now);

  // Clean old entries periodically
  for (const [k, ts] of recentVideos.entries()) {
    if (now - ts > DEDUP_WINDOW_MS) {
      recentVideos.delete(k);
    }
  }

  // Wait briefly for YouTube SPA title update if tab is accessible
  setTimeout(async () => {
    let title = "";
    try {
      const tab = await browser.tabs.get(details.tabId);
      if (tab && typeof tab.title === "string") {
        title = tab.title.replace(/\s*-\s*YouTube$/, "").trim();
      }
    } catch (_e) {
      title = "";
    }
    await sendNativeEvent({
      event: "youtube_start",
      video_id: videoId,
      title
    });
  }, 1500);
}

const YT_URL_FILTER = {
  url: [
    { hostSuffix: "youtube.com" },
    { hostEquals: "youtu.be" }
  ]
};

browser.webNavigation.onCommitted.addListener(handleYouTubeNavigation, YT_URL_FILTER);
browser.webNavigation.onHistoryStateUpdated.addListener(handleYouTubeNavigation, YT_URL_FILTER);

browser.downloads.onCreated.addListener((item) => {
  let filename = "unknown";
  if (item.filename) {
    const parts = item.filename.split(/[/\\]/);
    filename = parts[parts.length - 1] || "unknown";
  } else if (item.url) {
    try {
      const u = new URL(item.url);
      const segs = u.pathname.split("/").filter(Boolean);
      if (segs.length > 0) {
        filename = decodeURIComponent(segs[segs.length - 1]);
      }
    } catch (_e) {
      filename = "unknown";
    }
  }

  let sourceDomain = "unknown";
  if (item.url) {
    try {
      sourceDomain = new URL(item.url).hostname || "unknown";
    } catch (_e) {
      sourceDomain = "unknown";
    }
  }

  sendNativeEvent({
    event: "download_start",
    filename,
    source_domain: sourceDomain
  });
});
