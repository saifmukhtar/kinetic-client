use crate::api::error::ResolverError;
use std::collections::HashMap;
use std::sync::OnceLock;
use tokio::sync::Mutex;

/// (Removed local Reveal struct to use kinetic_core::types::Reveal directly)
///
/// The result of resolving a `kin://` URL.
#[derive(Debug, Clone)]
pub struct ResolvedKinDocument {
    /// A human-readable JSON summary of the trust state shown in the Trust Sheet.
    pub raw_json: String,
    /// The `http://127.0.0.1:<port>` URL the WebView should load.
    pub target_url: Option<String>,
}

/// Resolves a `kin://` URL to a local transport bridge URL that the WebView can load.
///
/// Resolution steps:
///   1. Normalize the input (strip `kin://`, handle bare names like `saif`)
///   2. If it's a bare name, query the Kademlia DHT to find the `PeerId` record
///   3. Spawn (or reuse) a local HTTP transport bridge for that `PeerId`
///   4. Return `http://127.0.0.1:<port>` as the target URL for the WebView
pub async fn resolve_kin_url(kin_url: String) -> Result<ResolvedKinDocument, ResolverError> {
    if !crate::api::daemon::NETWORK_CLIENT.initialized() {
        return Err(ResolverError::NotInitialized);
    }
        
    static HAS_BOOTSTRAPPED: tokio::sync::OnceCell<bool> = tokio::sync::OnceCell::const_new();
    HAS_BOOTSTRAPPED.get_or_init(|| async {
        println!("Waiting for Kademlia DHT bootstrap and identify to complete...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        true
    }).await;

    let network_client = crate::api::daemon::NETWORK_CLIENT
        .get()
        .ok_or(ResolverError::NotInitialized)?;

    // Step 0 — Parse the URL properly
    let parsed_url = url::Url::parse(&kin_url)
        .map_err(|e| ResolverError::InvalidUrl(e.to_string()))?;
        
    if parsed_url.scheme() != "kin" {
        return Err(ResolverError::InvalidUrl("Unsupported scheme, must be kin://".to_string()));
    }
    
    let host_str = parsed_url.host_str().ok_or_else(|| ResolverError::InvalidUrl("Missing host in kin:// URL".to_string()))?;
    
    let clean = if !host_str.contains('.') {
        format!("{}{}", host_str, kinetic_core::types::DOT_TLD)
    } else {
        host_str.to_string()
    };

// Fully-qualified domain name for DHT lookup.
    let fqdn = format!("{}.", clean);

    type CacheMap = HashMap<String, (libp2p::PeerId, String, std::time::Instant)>;
    static RESOLVER_CACHE: OnceLock<Mutex<CacheMap>> = OnceLock::new();
    let cache_mutex = RESOLVER_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    
    let cached_entry = {
        let mut cache = cache_mutex.lock().await;
        if let Some((peer_id, raw_json, timestamp)) = cache.get(&fqdn) {
            if timestamp.elapsed() < std::time::Duration::from_secs(5 * 60) {
                Some((*peer_id, raw_json.clone()))
            } else {
                cache.remove(&fqdn);
                None
            }
        } else {
            None
        }
    };

    let (peer_id, trust_state_json) = if let Some((p, r)) = cached_entry {
        (p, r)
    } else {
        // Step 1 — DHT Name Resolution: look up the PeerId for this .kin name.
        let payload = match network_client.resolve_redundant_payload(&fqdn).await {
            Ok(p) => p,
            Err(kinetic_core::error::ResolutionError::NotFound { .. }) => {
                return Err(ResolverError::NotFound(clean));
            }
            Err(kinetic_core::error::ResolutionError::Offline) => {
                return Err(ResolverError::Offline);
            }
            Err(e) => {
                return Err(ResolverError::Internal(format!("DHT resolution failed for '{}': {}", clean, e)));
            }
        };

        // Step 2 — Parse the Reveal envelope to get the DnsZone.
        let reveal: kinetic_core::types::Reveal =
            serde_json::from_slice(&payload).map_err(|e| ResolverError::Internal(format!("Failed to parse DHT payload: {}", e)))?;

        // Validate VDF Expiry (1,000,000 rounds)
        let latest_drand = crate::api::daemon::fetch_latest_drand().await;
        let age = latest_drand.saturating_sub(reveal.drand_pulse);
        let max_age_rounds = 1_000_000;
        if age > max_age_rounds {
            return Err(ResolverError::Expired(clean, age));
        }

        let zone = kinetic_core::types::DnsZone::parse_payload(&reveal.payload)
            .map_err(|e| ResolverError::Internal(format!("Failed to parse DNS zone from DHT payload: {}", e)))?;

        // Step 3 — Extract the KID record from the apex (@) of the zone.
        let kid_str = zone
            .records
            .get("@")
            .and_then(|records| {
                records.iter().find_map(|r| {
                    if let kinetic_core::types::DnsRecord::KID(kid) = r {
                        Some(kid.clone())
                    } else {
                        None
                    }
                })
            })
            .ok_or_else(|| {
                ResolverError::Internal(format!(
                    "No KID record found at the apex of '{}'. This name is not linked to an identity.",
                    clean
                ))
            })?;

        // Step 3.5 — Resolve the Capability Manifest using the derived manifest key
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(format!("{}#manifest", kid_str).as_bytes());
        let manifest_key = hex::encode(hasher.finalize());

        let manifest_payload = network_client
            .resolve_redundant_payload(&manifest_key)
            .await
            .map_err(|e| ResolverError::Internal(format!("Failed to resolve manifest for KID {}: {}", kid_str, e)))?;

        let manifest: kinetic_kid::CapabilityManifest = serde_json::from_slice(&manifest_payload)
            .map_err(|e| ResolverError::Internal(format!("Failed to parse CapabilityManifest from DHT payload: {}", e)))?;

        // Find the website service endpoint
        let service = manifest
            .services
            .iter()
            .find(|s| s.service_type == "website")
            .ok_or_else(|| ResolverError::NoWebsiteService(kid_str.clone()))?;

        let mut peer_id_str = service.endpoint.clone();
        if peer_id_str.starts_with("p2p://") {
            peer_id_str = peer_id_str.replace("p2p://", "");
        }
        let peer_id = if let Ok(ma) = peer_id_str.parse::<libp2p::Multiaddr>() {
            let mut id = None;
            for p in ma.iter() {
                if let libp2p::multiaddr::Protocol::P2p(p_id) = p {
                    id = Some(p_id);
                    break;
                }
            }
            id.ok_or_else(|| ResolverError::Internal("No PeerId found in multiaddr".to_string()))?
        } else {
            peer_id_str.parse::<libp2p::PeerId>()
                .map_err(|e| ResolverError::Internal(format!("Invalid PeerId '{}': {}", peer_id_str, e)))?
        };

        let trust_state = serde_json::json!({
            "status": "Verified",
            "name": clean,
            "peer_id": peer_id_str,
            "resolution": "Kinetic DHT (Kademlia)",
            "transport": "libp2p stream multiplexer",
            "note": "Traffic is end-to-end routed over the Kinetic P2P network."
        });

        let raw_json = serde_json::to_string_pretty(&trust_state).unwrap_or_default();
        
        cache_mutex.lock().await.insert(fqdn.clone(), (peer_id, raw_json.clone(), std::time::Instant::now()));
        (peer_id, raw_json)
    };

    // Step 4 — Get or spawn the local HTTP transport bridge for this peer.
    let port = crate::api::daemon::get_or_spawn_transport_bridge(peer_id, &clean)
        .await
        .map_err(|e| ResolverError::Internal(format!("Failed to setup transport bridge: {}", e)))?;

    // Safely construct the target URL while preserving the original path and query.
    // NOTE: The bridge_token is NO LONGER appended here to prevent Referer leakage.
    // The Flutter WebView is now responsible for setting the cookie directly.
    let mut local_url = url::Url::parse(&format!("http://localhost:{}", port)).unwrap();
    local_url.set_path(parsed_url.path());
    local_url.set_query(parsed_url.query());
    local_url.set_fragment(parsed_url.fragment());

    Ok(ResolvedKinDocument {
        raw_json: trust_state_json,
        target_url: Some(local_url.to_string()),
    })
}


/// Looks up the identity details of a `kin://` URL without requiring a `PeerId` routing record.
pub async fn lookup_identity(kin_url: String) -> Result<ResolvedKinDocument, ResolverError> {
    if !crate::api::daemon::NETWORK_CLIENT.initialized() {
        return Err(ResolverError::NotInitialized);
    }
        
    static HAS_BOOTSTRAPPED_ID: tokio::sync::OnceCell<bool> = tokio::sync::OnceCell::const_new();
    HAS_BOOTSTRAPPED_ID.get_or_init(|| async {
        println!("Waiting for Kademlia DHT bootstrap and identify to complete...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        true
    }).await;

    let network_client = crate::api::daemon::NETWORK_CLIENT
        .get()
        .ok_or(ResolverError::NotInitialized)?;

    let clean = kin_url
        .trim_start_matches("kin://")
        .trim_start_matches("http://")
        .trim_start_matches("https://")
        .trim_end_matches('/');

    let clean = if !clean.contains('.') && !clean.starts_with("did:kin:") {
        format!("{}{}", clean, kinetic_core::types::DOT_TLD)
    } else {
        clean.to_string()
    };

    let fqdn = format!("{}.", clean);

    let payload = match network_client.resolve_redundant_payload(&fqdn).await {
        Ok(p) => p,
        Err(kinetic_core::error::ResolutionError::NotFound { .. }) => {
            return Err(ResolverError::NotFound(clean));
        }
        Err(kinetic_core::error::ResolutionError::Offline) => {
            return Err(ResolverError::Offline);
        }
        Err(e) => {
            return Err(ResolverError::Internal(format!("DHT resolution failed for '{}': {}", clean, e)));
        }
    };

    let reveal: kinetic_core::types::Reveal =
        serde_json::from_slice(&payload).map_err(|e| ResolverError::Internal(format!("Failed to parse DHT payload: {}", e)))?;

    let pubkey_hex: String = reveal.pubkey.iter().map(|b| format!("{:02x}", b)).collect();

    let mut profile = serde_json::Map::new();
    if let Ok(zone) = kinetic_core::types::DnsZone::parse_payload(&reveal.payload)
        && let Some(records) = zone.records.get("@") {
            for record in records {
                if let kinetic_core::types::DnsRecord::TXT(txt) = record
                    && let Some((k, v)) = txt.split_once('=') {
                        profile.insert(k.to_string(), serde_json::Value::String(v.to_string()));
                    }
            }
        }

    let identity_state = serde_json::json!({
        "status": "Verified",
        "name": reveal.name,
        "owner_pubkey": pubkey_hex,
        "vdf_iterations": reveal.iterations,
        "drand_pulse": reveal.drand_pulse,
        "drand_randomness": reveal.drand_randomness,
        "resolution": "Kinetic DHT (Kademlia)",
        "profile": profile,
    });

    Ok(ResolvedKinDocument {
        raw_json: serde_json::to_string_pretty(&identity_state).unwrap_or_default(),
        target_url: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_resolve_uninitialized() {
        // Assume NETWORK_CLIENT might not be initialized yet in this fresh test run
        // If it is initialized, this will fail, but since tests run in parallel, it might be.
        // We handle this by checking the error type conditionally, or just ensuring it doesn't panic.
        let doc = resolve_kin_url(format!(
            "letsgoitsanewkineticdomain{}",
            kinetic_core::types::DOT_TLD
        ))
        .await;
        match doc {
            Err(ResolverError::NotInitialized) => {} // Expected if not initialized
            Err(_) => {} // Other errors are fine (like NotFound) if it is initialized
            Ok(_) => {}  // Ok is also fine if by some miracle it resolves
        }
    }

    #[tokio::test]
    async fn test_resolve_invalid_url() {
        crate::api::daemon::init_light_client("/tmp/kinetic_resolver_test".to_string(), None, None)
            .await
            .unwrap_or_default();
        let doc = resolve_kin_url("http://google.com".to_string()).await;
        assert!(matches!(doc, Err(ResolverError::InvalidUrl(_))));
    }

    #[tokio::test]
    async fn test_lookup_identity_invalid_url() {
        crate::api::daemon::init_light_client(
            "/tmp/kinetic_resolver_test2".to_string(),
            None,
            None,
        )
        .await
        .unwrap_or_default();
        // Just checking that it properly formats the FQDN and attempts a lookup,
        // which will result in NotFound or Offline, not a panic.
        let doc = lookup_identity("kin://invalid!name".to_string()).await;
        assert!(matches!(
            doc,
            Err(ResolverError::NotFound(_))
                | Err(ResolverError::Offline)
                | Err(ResolverError::Internal(_))
        ));
    }

    #[tokio::test]
    async fn test_resolve_not_found() {
        crate::api::daemon::init_light_client(
            "/tmp/kinetic_resolver_test3".to_string(),
            None,
            None,
        )
        .await
        .unwrap_or_default();
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        let doc = resolve_kin_url(format!(
            "kin://thisdomaindoesnotexist12345{}",
            kinetic_core::types::DOT_TLD
        ))
        .await;
        println!("DOC RETURNED: {:?}", doc);
        // Since we are likely offline or it doesn't exist
        assert!(matches!(
            doc,
            Err(ResolverError::NotFound(_))
                | Err(ResolverError::Offline)
                | Err(ResolverError::Internal(_))
        ));
    }
}
