// Keep-Alive Logic
import init, { KineticNode } from '../../public/wasm/kinetic_wasm.js';

let creating: Promise<void> | null = null;
async function setupOffscreenDocument(path: string) {
  // Firefox doesn't support or need the offscreen API because background scripts have DOM access.
  if (!chrome.offscreen) return;

  if (await hasOffscreenDocument(path)) return;
  if (creating) {
    await creating;
    return;
  }
  creating = chrome.offscreen.createDocument({
    url: path,
    reasons: [chrome.offscreen.Reason.LOCAL_STORAGE], // 'LOCAL_STORAGE' or 'DOM_PARSER' are valid reasons
    justification: 'Keep service worker running to maintain P2P network connections'
  });
  await creating;
  creating = null;
}

async function hasOffscreenDocument(path: string) {
  if (!chrome.offscreen) return false;
  
  // @ts-ignore - matchMedia is not available in service workers but offscreen API exists
  const matchedClients = await clients.matchAll();
  return matchedClients.some(
    (c: any) => c.url === chrome.runtime.getURL(path)
  );
}

// Node State
let nodeStatus = 'Starting up...';

async function startKineticNode() {
  try {
    console.log("Initializing Kinetic Wasm Node...");
    const wasmUrl = chrome.runtime.getURL('wasm/kinetic_wasm_bg.wasm');
    
    // Initialize Wasm
    await init({ module_or_path: wasmUrl });
    console.log("Wasm initialized.");

    // Create the Node with the JS Callback
    const node = new KineticNode((eventStr: string) => {
      console.log("EVENT FROM RUST:", eventStr);
      // Here we could broadcast events to the popup if it is open
      chrome.runtime.sendMessage({ type: 'NODE_EVENT', payload: eventStr }).catch(() => {});
    });

    // Start the node
    node.start();
    nodeStatus = 'Running';
    console.log("Node started successfully!");
  } catch (err) {
    console.error("Failed to start Wasm Node:", err);
    nodeStatus = 'Error: ' + err;
  }
}

const INTERCEPTOR_RULE_ID = 1;

async function setupInterceptorRule(enabled: boolean) {
  if (!chrome.declarativeNetRequest) return;
  
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [INTERCEPTOR_RULE_ID]
  });

  if (enabled) {
    const extensionUrl = chrome.runtime.getURL('resolve.html');
    await chrome.declarativeNetRequest.updateDynamicRules({
      addRules: [{
        id: INTERCEPTOR_RULE_ID,
        priority: 1,
        action: {
          type: 'redirect' as chrome.declarativeNetRequest.RuleActionType,
          redirect: {
            regexSubstitution: `${extensionUrl}?url=\\0`
          }
        },
        condition: {
          regexFilter: "^https?://([^/]+\\.kin)(/.*)?",
          resourceTypes: [
            'main_frame' as chrome.declarativeNetRequest.ResourceType,
            'sub_frame' as chrome.declarativeNetRequest.ResourceType
          ]
        }
      }]
    });
    console.log("Kinetic Interceptor enabled for .kin domains.");
  } else {
    console.log("Kinetic Interceptor disabled.");
  }
}

chrome.runtime.onInstalled.addListener(() => {
  setupOffscreenDocument('offscreen.html');
  startKineticNode();
  
  chrome.storage.local.get(['kinInterceptorEnabled'], (result) => {
    const enabled = result.kinInterceptorEnabled !== false; // default true
    if (result.kinInterceptorEnabled === undefined) {
      chrome.storage.local.set({ kinInterceptorEnabled: true });
    }
    setupInterceptorRule(enabled);
  });
});

chrome.runtime.onStartup.addListener(() => {
  setupOffscreenDocument('offscreen.html');
  startKineticNode();

  chrome.storage.local.get(['kinInterceptorEnabled'], (result) => {
    const enabled = result.kinInterceptorEnabled !== false;
    setupInterceptorRule(enabled);
  });
});

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace === 'local' && changes.kinInterceptorEnabled) {
    setupInterceptorRule(changes.kinInterceptorEnabled.newValue as boolean);
  }
});

// Listen for messages from the popup or keep-alive offscreen doc
chrome.runtime.onMessage.addListener((message: any, _sender: chrome.runtime.MessageSender, sendResponse: (response?: any) => void) => {
  if (message.type === 'KEEP_ALIVE') {
    // Just respond to keep the SW alive
    sendResponse({ ok: true });
    return false;
  }
  
  if (message.type === 'GET_STATUS') {
    sendResponse({ status: nodeStatus });
    return false;
  }

  if (message.type === 'PING_NODE') {
    console.log("Ping requested by user");
    // TODO: implement actual ping command to Rust
    sendResponse({ ok: true });
    return false;
  }

  return false;
});
