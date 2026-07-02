use anyhow::{Context, Result};


/// Public identity information for a .kin name, shown in the Identity tab.
#[derive(Debug, Clone)]
pub struct IdentityInfo {
    /// The resolved .kin name (e.g. `saif.kin`)
    pub name: String,
    /// The libp2p PeerId of the node that owns this name
    pub peer_id: String,
    /// Whether the name has an active VDF commitment
    pub is_active: bool,
    /// Human-readable note about the VDF / expiry status
    pub status_note: String,
}

/// Looks up a .kin name in the Kinetic DHT and returns its public identity info.
///
/// This is a read-only operation — it does not create or modify any data.
pub async fn fetch_identity(name: String) -> Result<IdentityInfo> {
    // Ensure the light client is running before any DHT queries.
    crate::api::daemon::init_light_client()
        .await
        .context("Failed to initialize Kinetic Light Client")?;

    let network_client = crate::api::daemon::NETWORK_CLIENT
        .get()
        .ok_or_else(|| anyhow::anyhow!("Network client not available"))?;

    // Normalize the name.
    let clean = name
        .trim_start_matches("kin://")
        .trim_end_matches('/')
        .trim_end_matches(".kin");
    let display_name = format!("{}.kin", clean);
    let fqdn = format!("{}.", display_name);

    // DHT lookup.
    let payload = match network_client.resolve_redundant_payload(&fqdn).await {
        Ok(p) => p,
        Err(kinetic_core::error::ResolutionError::NotFound { .. }) => {
            return Err(anyhow::anyhow!("'{}' was not found in the Kinetic network", display_name));
        }
        Err(kinetic_core::error::ResolutionError::Offline) => {
            return Err(anyhow::anyhow!("You appear to be offline. Cannot connect to the Kinetic network."));
        }
        Err(e) => {
            return Err(anyhow::anyhow!("DHT lookup failed for '{}': {}", display_name, e));
        }
    };

    let reveal: kinetic_core::types::Reveal =
        serde_json::from_slice(&payload).context("Failed to parse DHT payload")?;

    let zone = kinetic_core::types::DnsZone::parse_payload(&reveal.payload)
        .context("Failed to parse DNS zone")?;

    // Extract the PeerId from the apex record.
    let peer_id = zone
        .records
        .get("@")
        .and_then(|records| {
            records.iter().find_map(|r| {
                if let kinetic_core::types::DnsRecord::PeerId(pid) = r {
                    Some(pid.clone())
                } else {
                    None
                }
            })
        })
        .ok_or_else(|| {
            anyhow::anyhow!(
                "No PeerId record found for '{}'. The name is registered but no node is hosting it.",
                display_name
            )
        })?;

    // Check VDF expiry
    let latest_drand = crate::api::daemon::fetch_latest_drand().await;
    let age = latest_drand.saturating_sub(reveal.drand_pulse);
    let max_age_rounds = 1_000_000;
    
    let is_active = age <= max_age_rounds;
    let status_note = if is_active {
        "Active — VDF commitment is valid".to_string()
    } else {
        "Expired — VDF commitment has lapsed".to_string()
    };

    Ok(IdentityInfo {
        name: display_name,
        peer_id,
        is_active,
        status_note,
    })
}
