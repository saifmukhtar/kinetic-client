# Kinetic Client Error Reference

This document outlines the various domain-specific errors that can be thrown by the Kinetic FFI layer and propagated to the Flutter mobile client. It acts as a reference for developers to understand why an error occurred and how the application or the end-user should resolve it.

---

## 1. Resolver Errors
These errors occur during DNS-like resolution processes, typically when trying to resolve a Kinetic Identity (KID) to its routing information or when looking up domain manifests.

| Error | Message | Explanation | Resolution / Next Steps |
|-------|---------|-------------|-------------------------|
| `NotInitialized` | "Not initialized: call init_light_client() first" | The resolver was called before the daemon's core networking client was started. | Ensure the daemon is running before attempting to resolve a domain. |
| `Offline` | "You appear to be offline. Cannot connect to the Kinetic network." | The device cannot reach the network or the DHT is partitioned. | Check internet connection or wait for DHT recovery. |
| `NotFound` | "Name '{name}' was not found in the Kinetic network. It may be unregistered." | The domain name does not exist in the DHT, or has not been registered yet. | Verify the spelling of the domain or register it. |
| `Expired` | "The registration for '{name}' has expired ({rounds} rounds old)." | The domain exists but its registration proof is too old to be considered valid by the network. | The domain owner must broadcast a heartbeat or a new proof to renew it. |
| `InvalidUrl` | "Invalid URL format: {url}" | The provided URL does not conform to the expected `kin://` or raw domain formatting. | Sanitize input in the address bar before passing to the resolver. |
| `NoWebsiteService` | "No 'website' service found in manifest for KID {kid}" | The domain successfully resolved, but the identity hasn't explicitly published a website routing service. | The identity owner needs to update their manifest to include website routing endpoints. |
| `Internal` | "Internal error: {msg}" | An unexpected failure inside the Rust core (e.g. JSON parsing failure or memory issue). | Check the internal `{msg}` for debugging information. |

---

## 2. Delegation Errors
These errors are associated with the cryptographic Domain Registration, Proof-of-Work VDF (Verifiable Delay Function) generation, and DHT broadcasting.

| Error | Message | Explanation | Resolution / Next Steps |
|-------|---------|-------------|-------------------------|
| `NotInitialized` | "Not initialized: call init_light_client() first" | The broadcast function was called before the core networking client was initialized. | Ensure the daemon is running first. |
| `InvalidPrivateKey` | "Private key must be exactly 32 bytes" | The Ed25519 signing scalar provided from secure storage is corrupt or improperly formatted. | The local registration state may be corrupted; require the user to restart registration. |
| `InvalidName` | "Name '{name}' contains invalid characters" | Kinetic domains typically only allow alphanumeric characters and hyphens. | Validate input on the Flutter side before invoking the FFI. |
| `NameTooShort` | "Name must be at least 8 characters long" | Short domains are restricted on mobile clients due to the difficulty required to mine them. | Prompt the user to pick a longer domain name. |
| `DrandFetchFailed` | "Failed to fetch drand randomness from all endpoints" | The client could not connect to the League of Entropy drand network to fetch the latest random pulse. | Retry when internet connectivity improves or the drand endpoints are available. |
| `InvalidProof` | "VDF proof invalid or rejected: {msg}" | The delegated node returned a VDF proof that did not mathematically satisfy the challenge. | The delegated miner may be misconfigured or malicious. |
| `ProofTooLong` | "VDF proof string exceeds maximum allowed length" | The node returned an oversized VDF payload, potentially to cause memory exhaustion. | Discard the proof and attempt to connect to a different delegated miner. |
| `Internal` | "Internal error: {msg}" | An unexpected failure inside the Rust core. | Check the internal `{msg}` for debugging information. |

---

## 3. Daemon Errors
These errors relate to the lifecycle of the P2P networking daemon (Kademlia DHT + Gossipsub) and the local HTTP proxy server.

| Error | Message | Explanation | Resolution / Next Steps |
|-------|---------|-------------|-------------------------|
| `AlreadyInitialized` | "Network client already initialized" | An attempt was made to start the daemon when it is already running. | Safe to ignore, or check daemon status before calling init. |
| `NotInitialized` | "Not initialized: call init_light_client() first" | An operation was called that requires the daemon to be active. | Start the daemon. |
| `InvalidAppDirectory` | "Invalid app directory provided" | The path provided to the FFI for storing persistent network data is inaccessible. | Ensure Flutter's `getApplicationDocumentsDirectory()` is yielding a valid path. |
| `ProxyStartFailed` | "Failed to start proxy server: {msg}" | The local `127.0.0.1:8080` HTTP proxy could not bind to the port. | The port may be in use by another app, or OS permissions are blocking it. |
| `Internal` | "Internal error: {msg}" | An unexpected failure inside the Rust core. | Check the internal `{msg}` for debugging information. |

---

## 4. Identity Errors
These errors are related to fetching raw Identity profiles and public keys directly from the DHT.

| Error | Message | Explanation | Resolution / Next Steps |
|-------|---------|-------------|-------------------------|
| `NotInitialized` | "Not initialized: call init_light_client() first" | The identity fetcher was called before the core networking client was initialized. | Ensure the daemon is running first. |
| `Offline` | "You appear to be offline. Cannot connect to the Kinetic network." | The device cannot reach the network or the DHT is partitioned. | Check internet connection. |
| `NotFound` | "Identity '{name}' was not found in the Kinetic network." | The identity is not registered or has fallen out of the DHT cache. | Verify the name or wait for the owner to broadcast a heartbeat. |
| `Internal` | "Internal error: {msg}" | An unexpected failure inside the Rust core. | Check the internal `{msg}` for debugging information. |
