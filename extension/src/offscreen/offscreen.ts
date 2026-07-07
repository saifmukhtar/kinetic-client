// This script runs in the offscreen document and periodically pings the service worker
// to prevent it from suspending (Manifest V3 30-second idle limit).

setInterval(() => {
  if (chrome.runtime) {
    chrome.runtime.sendMessage({ type: 'KEEP_ALIVE' }).catch(() => {
      // Ignore errors if the background script hasn't loaded yet
    });
  }
}, 20000); // Send a ping every 20 seconds
