use anyhow::{Context, Result};

/// (Removed local Reveal struct to use kinetic_core::types::Reveal directly)

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
pub async fn resolve_kin_url(kin_url: String) -> Result<ResolvedKinDocument> {
    if !crate::api::daemon::NETWORK_CLIENT.initialized() {
        return Err(anyhow::anyhow!("Kinetic Light Client is not initialized"));
    }
        
    static HAS_BOOTSTRAPPED: tokio::sync::OnceCell<bool> = tokio::sync::OnceCell::const_new();
    HAS_BOOTSTRAPPED.get_or_init(|| async {
        println!("Waiting for Kademlia DHT bootstrap and identify to complete...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        true
    }).await;

    let network_client = crate::api::daemon::NETWORK_CLIENT
        .get()
        .ok_or_else(|| anyhow::anyhow!("Network client not available"))?;

    // Step 0 — Parse the URL properly
    let parsed_url = url::Url::parse(&kin_url)
        .map_err(|e| anyhow::anyhow!("Invalid URL format: {}", e))?;
        
    if parsed_url.scheme() != "kin" {
        return Err(anyhow::anyhow!("Unsupported scheme, must be kin://"));
    }
    
    let host_str = parsed_url.host_str().ok_or_else(|| anyhow::anyhow!("Missing host in kin:// URL"))?;
    
    let clean = if !host_str.contains('.') {
        format!("{}.kin", host_str)
    } else {
        host_str.to_string()
    };

    // Fully-qualified domain name for DHT lookup.
    let fqdn = format!("{}.", clean);

    // Step 1 — DHT Name Resolution: look up the PeerId for this .kin name.
    let payload = match network_client.resolve_redundant_payload(&fqdn).await {
        Ok(p) => p,
        Err(kinetic_core::error::ResolutionError::NotFound { .. }) => {
            return Err(anyhow::anyhow!("Name '{}' was not found in the Kinetic network. It may be unregistered.", clean));
        }
        Err(kinetic_core::error::ResolutionError::Offline) => {
            return Err(anyhow::anyhow!("You appear to be offline. Cannot connect to the Kinetic network."));
        }
        Err(e) => {
            return Err(anyhow::anyhow!("DHT resolution failed for '{}': {}", clean, e));
        }
    };

    // Step 2 — Parse the Reveal envelope to get the DnsZone.
    let reveal: kinetic_core::types::Reveal =
        serde_json::from_slice(&payload).context("Failed to parse DHT payload")?;

    // Validate VDF Expiry (1,000,000 rounds)
    let latest_drand = crate::api::daemon::fetch_latest_drand().await;
    let age = latest_drand.saturating_sub(reveal.drand_pulse);
    let max_age_rounds = 1_000_000;
    if age > max_age_rounds {
        return Err(anyhow::anyhow!(
            "Resolution failed: The registration for '{}' has expired ({} rounds old).",
            clean, age
        ));
    }

    let zone = kinetic_core::types::DnsZone::parse_payload(&reveal.payload)
        .context("Failed to parse DNS zone from DHT payload")?;

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
            anyhow::anyhow!(
                "No KID record found at the apex of '{}'. This name is not linked to an identity.",
                clean
            )
        })?;

    // Step 3.5 — Resolve the Capability Manifest using the derived manifest key
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(format!("{}#manifest", kid_str).as_bytes());
    let manifest_key = hex::encode(hasher.finalize());

    let manifest_payload = network_client
        .resolve_redundant_payload(&manifest_key)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to resolve manifest for KID {}: {}", kid_str, e))?;

    let manifest: kinetic_kid::CapabilityManifest = serde_json::from_slice(&manifest_payload)
        .context("Failed to parse CapabilityManifest from DHT payload")?;

    // Find the website service endpoint
    let service = manifest
        .services
        .iter()
        .find(|s| s.service_type == "website")
        .ok_or_else(|| anyhow::anyhow!("No 'website' service found in manifest for KID {}", kid_str))?;

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
        id.ok_or_else(|| anyhow::anyhow!("No PeerId found in multiaddr"))?
    } else {
        peer_id_str.parse::<libp2p::PeerId>()
            .map_err(|e| anyhow::anyhow!("Invalid PeerId '{}': {}", peer_id_str, e))?
    };

    // Step 4 — Get or spawn the local HTTP transport bridge for this peer.
    let port = crate::api::daemon::get_or_spawn_transport_bridge(peer_id, &clean)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to setup transport bridge: {}", e))?;

    let trust_state = serde_json::json!({
        "status": "Verified",
        "name": clean,
        "peer_id": peer_id_str,
        "resolution": "Kinetic DHT (Kademlia)",
        "transport": "libp2p stream multiplexer",
        "note": "Traffic is end-to-end routed over the Kinetic P2P network."
    });

    let raw_json = serde_json::to_string_pretty(&trust_state).unwrap_or_default();
    let token = crate::api::daemon::get_bridge_token();
    
    // Safely construct the target URL while preserving the original path and query,
    // and injecting the bridge_token securely.
    let mut local_url = url::Url::parse(&format!("http://localhost:{}", port)).unwrap();
    local_url.set_path(parsed_url.path());
    local_url.set_query(parsed_url.query());
    local_url.set_fragment(parsed_url.fragment());
    
    // Append the original query parameters, and then forcibly append the bridge_token
    let mut query_pairs = parsed_url.query_pairs().into_owned().collect::<Vec<_>>();
    // Remove any malicious attempt to spoof the bridge_token from the deep link
    query_pairs.retain(|(k, _)| k != "bridge_token");
    query_pairs.push(("bridge_token".to_string(), token));
    
    let mut query_ser = url::form_urlencoded::Serializer::new(String::new());
    for (k, v) in query_pairs {
        query_ser.append_pair(&k, &v);
    }
    local_url.set_query(Some(&query_ser.finish()));

    Ok(ResolvedKinDocument {
        raw_json,
        target_url: Some(local_url.to_string()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_resolve() {
        crate::api::daemon::init_light_client("/tmp".to_string(), None).await.unwrap();
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        let doc = crate::api::resolver::resolve_kin_url("letsgoitsanewkineticdomain.kin".to_string()).await;
        println!("Resolve result: {:?}", doc);
    }
}

/// Looks up the identity details of a `kin://` URL without requiring a `PeerId` routing record.
pub async fn lookup_identity(kin_url: String) -> Result<ResolvedKinDocument> {
    if !crate::api::daemon::NETWORK_CLIENT.initialized() {
        return Err(anyhow::anyhow!("Kinetic Light Client is not initialized"));
    }
        
    static HAS_BOOTSTRAPPED_ID: tokio::sync::OnceCell<bool> = tokio::sync::OnceCell::const_new();
    HAS_BOOTSTRAPPED_ID.get_or_init(|| async {
        println!("Waiting for Kademlia DHT bootstrap and identify to complete...");
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        true
    }).await;

    let network_client = crate::api::daemon::NETWORK_CLIENT
        .get()
        .ok_or_else(|| anyhow::anyhow!("Network client not available"))?;

    let clean = kin_url
        .trim_start_matches("kin://")
        .trim_start_matches("http://")
        .trim_start_matches("https://")
        .trim_end_matches('/');

    let clean = if !clean.contains('.') && !clean.starts_with("did:kin:") {
        format!("{}.kin", clean)
    } else {
        clean.to_string()
    };

    let fqdn = format!("{}.", clean);

    let payload = match network_client.resolve_redundant_payload(&fqdn).await {
        Ok(p) => p,
        Err(kinetic_core::error::ResolutionError::NotFound { .. }) => {
            return Err(anyhow::anyhow!("Name '{}' was not found in the Kinetic network. It may be unregistered.", clean));
        }
        Err(kinetic_core::error::ResolutionError::Offline) => {
            return Err(anyhow::anyhow!("You appear to be offline. Cannot connect to the Kinetic network."));
        }
        Err(e) => {
            return Err(anyhow::anyhow!("DHT resolution failed for '{}': {}", clean, e));
        }
    };

    let reveal: kinetic_core::types::Reveal =
        serde_json::from_slice(&payload).context("Failed to parse DHT payload")?;

    let pubkey_hex: String = reveal.pubkey.iter().map(|b| format!("{:02x}", b)).collect();

    let mut profile = serde_json::Map::new();
    if let Ok(zone) = kinetic_core::types::DnsZone::parse_payload(&reveal.payload) {
        if let Some(records) = zone.records.get("@") {
            for record in records {
                if let kinetic_core::types::DnsRecord::TXT(txt) = record {
                    if let Some((k, v)) = txt.split_once('=') {
                        profile.insert(k.to_string(), serde_json::Value::String(v.to_string()));
                    }
                }
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
