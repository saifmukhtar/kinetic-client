use kinetic_core::types::{is_valid_apex_name, normalize_name, VdfJobRequest, Reveal, VdfProof, Heartbeat};
use flutter_rust_bridge::frb;
use sha2::{Sha256, Digest};
use anyhow::Result;
use ed25519_dalek::{SigningKey, Signer};
use serde::{Deserialize, Serialize};
use nostr_sdk::prelude::*;

/// Validates that a requested domain name meets the mobile delegation rules.
/// Specifically, the name must be at least 8 characters long.
#[frb(sync)]
pub fn validate_delegation_name(name: &str) -> Result<bool> {
    if !is_valid_apex_name(name) {
        return Ok(false);
    }
    
    let fqdn = normalize_name(name);
    let len = fqdn.trim_end_matches(".kin").len();
    if len < 8 {
        return Ok(false);
    }
    Ok(true)
}

/// Derives the Ed25519 verifying (public) key bytes from a 32-byte signing (private) key.
/// Used by the HTTP VDF request flow to send the correct pubkey to the desktop node.
#[frb(sync)]
pub fn derive_public_key_bytes_sync(private_key_bytes: Vec<u8>) -> Result<Vec<u8>> {
    let key_bytes: [u8; 32] = private_key_bytes
        .try_into()
        .map_err(|_| anyhow::anyhow!("Private key must be exactly 32 bytes"))?;
    let signing_key = SigningKey::from_bytes(&key_bytes);
    Ok(signing_key.verifying_key().to_bytes().to_vec())
}

/// Helper function to check if the hash has the required number of leading zero bits.
fn check_leading_zeros(hash: &[u8], target_bits: u32) -> bool {
    let mut bits_found = 0;
    for &byte in hash {
        let leading_zeros = byte.leading_zeros();
        bits_found += leading_zeros;
        
        if bits_found >= target_bits {
            return true;
        }
        
        if byte != 0 {
            break;
        }
    }
    false
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VdfJobResponse {
    pub challenge_hex: String,
    pub salt: Vec<u8>,
    pub drand_pulse: u64,
    pub drand_randomness: String,
    pub iterations: u64,
}

/// Prepares and encrypts a VDF proof request for a Nostr NIP-04 Direct Message
pub async fn prepare_vdf_request_nostr(
    desktop_npub: String, 
    name: String, 
    private_key_bytes: Vec<u8>,
    difficulty_bits: u32
) -> Result<(VdfJobResponse, String)> {
    
    let fqdn = normalize_name(&name);
    let len = fqdn.trim_end_matches(".kin").len();
    if len < 8 {
        return Err(anyhow::anyhow!("Name must be at least 8 characters long"));
    }

    let key_bytes: [u8; 32] = private_key_bytes.try_into()
        .map_err(|_| anyhow::anyhow!("Private key must be exactly 32 bytes"))?;
    
    let secret_key = SecretKey::from_slice(&key_bytes)?;
    let keys = Keys::new(secret_key);

    let desktop_pubkey = PublicKey::parse(&desktop_npub)?;

    // Fetch drand pulse via the shared multi-URL fallback helper (fix: was single-URL SPOF)
    let round = crate::api::daemon::fetch_latest_drand().await;
    // Re-fetch full JSON for randomness field (needed for commitment hash)
    let drand_urls = [
        "https://api.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
        "https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
        "https://api2.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
    ];
    let mut randomness = String::new();
    for url in drand_urls.iter() {
        if let Ok(resp) = reqwest::get(*url).await {
            if let Ok(json) = resp.json::<serde_json::Value>().await {
                if let Some(r) = json["randomness"].as_str() {
                    randomness = r.to_string();
                    break;
                }
            }
        }
    }
    if randomness.is_empty() {
        return Err(anyhow::anyhow!("Failed to fetch drand randomness from all endpoints"));
    }

    let mut salt = [0u8; 32];
    getrandom::getrandom(&mut salt).map_err(|e| anyhow::anyhow!("Failed to generate salt: {}", e))?;
    
    let challenge_bytes = hex::decode(&randomness).unwrap_or_else(|_| vec![0u8; 32]);

    // Construct Commitment Hash
    let mut hasher = Sha256::new();
    hasher.update(fqdn.as_bytes());
    hasher.update(&salt);
    hasher.update(&challenge_bytes);
    hasher.update(&keys.public_key().to_bytes());
    let mut challenge_hash = [0u8; 32];
    challenge_hash.copy_from_slice(&hasher.finalize());

    // Perform Hashcash PoW
    let mut nonce: u64 = 0;
    loop {
        let mut h = Sha256::new();
        h.update(&challenge_hash);
        h.update(&nonce.to_le_bytes());
        let result = h.finalize();
        if check_leading_zeros(&result, difficulty_bits) {
            break;
        }
        nonce += 1;
    }

    let req = VdfJobRequest {
        challenge_hash: challenge_hash,
        name_length: len as u8,
        hashcash_nonce: nonce,
        drand_pulse: round,
        pin: None,
    };

    let req_json = serde_json::to_string(&req)?;
    let encrypted_content = nip04::encrypt(keys.secret_key(), &desktop_pubkey, req_json)?;
    
    // Edge Cases 164 & 169: Use Drand round to calculate exact current time to prevent clock skew relay rejections
    // Drand mainnet genesis is 1595431050,    // Kinetic uses Quicknet params, not Mainnet.
    let drand_timestamp = 1692803367 + (round * 3);
    let timestamp = Timestamp::from(drand_timestamp as u64);
    
    let event = EventBuilder::new(Kind::EncryptedDirectMessage, encrypted_content, [Tag::public_key(desktop_pubkey)])
        .custom_created_at(timestamp)
        .to_event(&keys)?;
    let event_json = event.as_json();

    let response = VdfJobResponse {
        challenge_hex: hex::encode(challenge_hash),
        salt: salt.to_vec(),
        drand_pulse: round,
        drand_randomness: randomness,
        iterations: 0,
    };

    Ok((response, event_json))
}

/// Decrypts a VDF proof response received via Nostr NIP-04 Direct Message
pub fn decrypt_vdf_proof_nostr(
    desktop_npub: String,
    private_key_bytes: Vec<u8>,
    encrypted_content: String
) -> Result<Vec<u8>> {
    let key_bytes: [u8; 32] = private_key_bytes.try_into()
        .map_err(|_| anyhow::anyhow!("Private key must be exactly 32 bytes"))?;
    
    let secret_key = SecretKey::from_slice(&key_bytes)?;
    let desktop_pubkey = PublicKey::parse(&desktop_npub)?;
    
    let decrypted = nip04::decrypt(&secret_key, &desktop_pubkey, encrypted_content)?;
    
    let proof_json: serde_json::Value = serde_json::from_str(&decrypted)?;
    if let Some(proof_hex) = proof_json["proof_bytes"].as_str() {
        if proof_hex.len() > 1024 {
            return Err(anyhow::anyhow!("VDF proof string exceeds maximum allowed length"));
        }
        let proof_bytes = hex::decode(proof_hex)?;
        return Ok(proof_bytes);
    }
    
    Err(anyhow::anyhow!("Invalid proof format from desktop node"))
}

pub async fn broadcast_mobile_reveal(
    name: String,
    payload: Vec<u8>,
    private_key_bytes: Vec<u8>,
    vdf_proof_bytes: Vec<u8>,
    salt: Vec<u8>,
    drand_pulse: u64,
    drand_randomness: String,
) -> Result<bool> {
    let fqdn = normalize_name(&name);
    
    let key_bytes: [u8; 32] = private_key_bytes.try_into()
        .map_err(|_| anyhow::anyhow!("Private key must be exactly 32 bytes"))?;
    let signing_key = SigningKey::from_bytes(&key_bytes);
    let pubkey = signing_key.verifying_key().to_bytes().to_vec();

    let required_iters = kinetic_core::consensus_math::ConsensusParams::default().required_iterations(&fqdn, drand_pulse, &pubkey);

    let mut salt_arr = [0u8; 32];
    if salt.len() >= 32 {
        salt_arr.copy_from_slice(&salt[..32]);
    }

    let mut reveal = Reveal {
        protocol_version: 2,
        name: fqdn.clone(),
        payload,
        salt: salt_arr,
        drand_pulse,
        drand_randomness,
        iterations: required_iters,
        vdf_proof: VdfProof { proof_bytes: vdf_proof_bytes },
        pubkey,
        signature: vec![],
    };

    let signable = reveal.signable_bytes();
    reveal.signature = signing_key.sign(&signable).to_bytes().to_vec();

    let reveal_bytes = serde_json::to_vec(&reveal)?;

    if let Some(network) = crate::api::daemon::NETWORK_CLIENT.get() {
        network.publish_redundant_payload(&fqdn, reveal_bytes).await?;
        Ok(true)
    } else {
        Err(anyhow::anyhow!("Network client not initialized"))
    }
}

pub async fn broadcast_mobile_heartbeat(name: String, private_key_bytes: Vec<u8>) -> Result<bool> {
    let fqdn = normalize_name(&name);

    let key_bytes: [u8; 32] = private_key_bytes.try_into()
        .map_err(|_| anyhow::anyhow!("Private key must be exactly 32 bytes"))?;
    let signing_key = SigningKey::from_bytes(&key_bytes);

    // Use the shared multi-URL fallback Drand helper (fix: was single-URL SPOF)
    let round = crate::api::daemon::fetch_latest_drand().await;

    let mut heartbeat = Heartbeat {
        name: fqdn.clone(),
        latest_drand_pulse: round,
        signature: vec![],
    };

    let signable = heartbeat.signable_bytes();
    heartbeat.signature = signing_key.sign(&signable).to_bytes().to_vec();

    let hb_bytes = serde_json::to_vec(&heartbeat)?;

    if let Some(network) = crate::api::daemon::NETWORK_CLIENT.get() {
        network.publish_redundant_payload(&fqdn, hb_bytes).await?;
        Ok(true)
    } else {
        Err(anyhow::anyhow!("Network client not initialized"))
    }
}
