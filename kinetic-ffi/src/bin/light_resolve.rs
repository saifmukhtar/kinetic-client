use anyhow::Result;
use kinetic_network::{NetworkConfig, NetworkEventLoop, NetworkMode};
use kinetic_storage::SledStorage;
use std::env;
use std::sync::Arc;
use tokio::sync::watch;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    // 1. Get the domain name to resolve
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <domain.kin> <bootstrap_peer_multiaddr>", args[0]);
        std::process::exit(1);
    }
    let name = &args[1];
    let bootstrap_peer = &args[2];

    println!("[*] Starting Kinetic Light Client Resolution for: {}", name);

    // 2. Setup ephemeral storage and keys for the light client
    let temp_dir = env::temp_dir().join(format!("kinetic-light-client-{}", std::process::id()));
    let storage = Arc::new(SledStorage::new(&temp_dir)?);
    println!("[*] Generating ephemeral identity for Light Client...");
    let local_key = libp2p::identity::Keypair::generate_ed25519();
    let (_, drand_rx) = watch::channel(0);

    // 3. Configure as LightClient with a single bootstrap peer
    let config = NetworkConfig {
        mode: NetworkMode::LightClient,
        listen_addr: "".to_string(),
        external_address: None,
        bootstrap_nodes: vec![bootstrap_peer.to_string()],
        initial_drand_pulse: 1000,
        enable_mdns: false,
        seed_domains: vec![],
    };

    // We don't have the exact PeerId of the daemon. Let's just dial the address directly without /p2p/
    // wait, we can't use bootstrap_nodes without PeerId in Kad. 
    // Let's connect the swarm manually.

    let (client, event_loop) = NetworkEventLoop::new(
        config.clone(),
        local_key,
        storage,
        drand_rx,
        None,
    )?;

    // Spawn event loop in background
    tokio::spawn(async move {
        event_loop.run().await;
    });

    // 4. Wait for libp2p to establish connection and identify to complete
    println!("[*] Waiting for libp2p bootstrap connection to establish...");
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    
    println!("[*] Querying Kademlia DHT for name: {}", name);
    let payload = client.resolve_redundant_payload(name).await?;

    if let Some(data) = payload {
        if let Ok(text) = String::from_utf8(data.clone()) {
            println!("\n[+] SUCCESS: Resolved payload (UTF-8): {}", text);
        } else {
            println!("\n[+] SUCCESS: Resolved payload (Bytes): {:?}", data);
        }
    } else {
        println!("\n[-] FAILED: Name not found in DHT");
    }

    Ok(())
}
