# Kinetic Client Privacy Policy

**Last Updated:** July 7, 2026

This Privacy Policy describes how the Kinetic Client browser extension ("the Extension") collects, uses, and protects your information.

## 1. Data Collection

**We do not collect any personal data.**  
The Extension is designed to operate completely locally on your device as a light node for the decentralized Kinetic Network. By running the extension, you actively participate in the Kinetic network and help secure the mesh. 

- **No Analytics:** We do not use Google Analytics, tracking pixels, or any third-party analytics software.
- **No Browsing History:** We do not track, store, or transmit the websites you visit. 
- **No Personal Information:** We do not require an account, email address, or any personally identifiable information (PII) to use the Extension.

## 2. Network Communications

The Extension intercepts navigation to `.kin` domains locally on your machine using the `declarativeNetRequest` API. It resolves these domains by communicating with the decentralized Kinetic DHT (Distributed Hash Table) network. 

- These network requests are entirely decentralized and do not route through any centralized servers owned by us.
- The requests contain only the data necessary to resolve the domain (e.g., querying the hash of the domain name). No identifying metadata is attached to these requests.

## 3. Local Storage

The Extension uses your browser's local `storage` API strictly to save:
- Your personal Extension preferences/settings.
- A local cache of recently resolved `.kin` domains to improve future loading speeds.

This data never leaves your device and is never transmitted to any external servers.

## 4. Changes to this Policy

If we change our privacy practices, we will update this Privacy Policy. Because the Extension does not collect personal information, any changes will only be to reflect updates in the decentralized network protocol.

## 5. Contact

If you have any questions about this Privacy Policy, please open an issue on our GitHub repository.
