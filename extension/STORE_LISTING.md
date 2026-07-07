# Store Listing Metadata

This document contains all the copy, descriptions, and permission justifications needed when publishing the Kinetic Client to the Chrome Web Store, Firefox Add-ons (AMO), and Opera Add-ons. Keep this file updated if the extension changes.

## 1. Extension Details

**Name:** Kinetic Client  
**Short Summary:** Browse .kin domains securely while running a lightweight Kinetic Network node in your browser.

**Full Description:**  
Kinetic Client is your gateway to the decentralized web. This extension serves two primary purposes:

1. **Seamless Browsing:** It allows you to natively resolve and view `.kin` domains (e.g., `saif.kin`) directly in your browser without relying on centralized DNS servers.
2. **Network Participation:** By simply having the extension installed, you run a light node that actively participates in the Kinetic network and helps secure the mesh.

The extension operates completely locally, maintaining a secure connection to the network to resolve domains quickly and transparently.

## 2. Permissions Justifications (For Reviewers)

When submitting to Firefox AMO and Chrome, you must provide explicit justifications for every permission requested in `manifest.json`. **Copy and paste these exact justifications into the "Notes to Reviewers" or Permissions Justification fields:**

* **`declarativeNetRequest` & `*://*.kin/*` (Host Permission):** 
  We use this to intercept browser navigation to `.kin` domains. Because `.kin` is a decentralized top-level domain, standard DNS cannot resolve it. This permission allows us to dynamically redirect the user's request to the correct resolved IP address or decentralized gateway on the Kinetic network.
* **`offscreen`:** 
  We use the offscreen permission to maintain a persistent WebSocket connection and process Distributed Hash Table (DHT) network tasks in the background. Because Service Workers sleep after 30 seconds, the offscreen document is necessary to keep the light node continuously participating in the Kinetic network without interrupting the user.
* **`alarms`:** 
  We use alarms to periodically ping the network (e.g., every 5 minutes) to ensure the light node remains actively connected and synchronized with the Kinetic DHT.
* **`storage`:** 
  Used to save user settings, preferences, and locally cache domain resolutions to improve loading speeds for frequently visited `.kin` domains.

## 3. Privacy Policy (Mandatory)

**Data Collection & Usage:**
The Kinetic Client extension operates entirely locally as a decentralized light node. 
- It **does not** collect, store, or transmit any personal user data.
- It **does not** track, collect, or transmit your browsing history.
- It **does not** use any third-party analytics trackers.

The extension only communicates with the decentralized Kinetic Network to resolve `.kin` domains and participate in DHT routing. No identifying information is attached to these network requests.

## 4. Notes to Reviewers (Crucial for Firefox / Opera)

*When submitting your `.zip` file, paste this into the Notes to Reviewers box:*

> "This extension is a light client for the decentralized Kinetic naming network. Because it is built with Vite, the JavaScript in the `.zip` is minified. I have attached the original source code repository for your review. 
> To test the extension, simply install it and attempt to navigate to a `.kin` domain (like `http://saif.kin`). The extension uses `declarativeNetRequest` to intercept this navigation and route it through our decentralized network. It uses an offscreen document to maintain the DHT connection."
