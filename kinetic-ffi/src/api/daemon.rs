use kinetic_network::{NetworkClient, NetworkEventLoop, NetworkConfig, NetworkMode};
use kinetic_storage::SledStorage;
use std::sync::Arc;
use tokio::sync::{OnceCell, Mutex, watch};
use anyhow::Result;
use std::collections::HashMap;
use axum::{
    extract::{Request, State},
    response::Response,
    routing::any,
    Router,
};
use axum::http::StatusCode;

use crate::api::bootstrap;

/// The global network client singleton.
/// Initialized once via `init_light_client()` and reused for all DHT queries.
pub static NETWORK_CLIENT: OnceCell<Arc<NetworkClient>> = OnceCell::const_new();

use flutter_rust_bridge::frb;

#[frb(ignore)]
pub(crate) struct BridgeInfo {
    pub port: u16,
    pub last_accessed: std::time::Instant,
    pub shutdown_tx: tokio::sync::oneshot::Sender<()>,
}

#[frb(ignore)]
pub(crate) static TRANSPORT_BRIDGES: OnceCell<Arc<Mutex<HashMap<String, BridgeInfo>>>> = OnceCell::const_new();

/// A randomly generated token that must be provided by the WebView 
/// (via query param or cookie) to access the localhost transport bridge.
pub static BRIDGE_TOKEN: std::sync::OnceLock<String> = std::sync::OnceLock::new();

/// Returns the current bridge authentication token.
pub fn get_bridge_token() -> String {
    BRIDGE_TOKEN.get_or_init(|| {
        libp2p::identity::Keypair::generate_ed25519().public().to_peer_id().to_string()
    }).clone()
}

/// Initializes the Kinetic Light Client. Safe to call multiple times —
/// subsequent calls are no-ops. Uses production bootstrap nodes by default.
pub async fn init_light_client() -> Result<()> {
    if NETWORK_CLIENT.initialized() {
        return Ok(());
    }

    let mut base_tmp = std::path::PathBuf::new();
    let paths = [
        "/data/user/0/dev.saifmukhtar.kinetic/app_flutter",
        "/data/data/dev.saifmukhtar.kinetic/app_flutter",
        "/data/user/0/dev.saifmukhtar.kinetic/cache",
        "/data/data/dev.saifmukhtar.kinetic/cache"
    ];
    for p in paths.iter() {
        let path = std::path::PathBuf::from(p);
        if std::fs::create_dir_all(&path).is_ok() {
            base_tmp = path;
            break;
        }
    }

    let storage_dir = base_tmp.join("kinetic_light_storage");
    std::fs::create_dir_all(&storage_dir)?;
    let storage = Arc::new(SledStorage::new(&storage_dir)?);

    let current_round = fetch_latest_drand().await;

    let identity_path = base_tmp.join("kinetic_identity.bin");
    let local_key = if let Ok(bytes) = std::fs::read(&identity_path) {
        if let Ok(key) = libp2p::identity::Keypair::from_protobuf_encoding(&bytes) {
            let peer_id = key.public().to_peer_id();
            if kinetic_network::pow::is_valid_sybil_pow(&peer_id, current_round, kinetic_network::pow::DEFAULT_DIFFICULTY_BITS) {
                key
            } else {
                tracing::info!("Cached PoW identity expired for current epoch. Mining a new one...");
                let k = kinetic_network::pow::mine_sybil_keypair(current_round, kinetic_network::pow::DEFAULT_DIFFICULTY_BITS);
                let _ = std::fs::write(&identity_path, k.to_protobuf_encoding().unwrap());
                k
            }
        } else {
            let k = kinetic_network::pow::mine_sybil_keypair(current_round, kinetic_network::pow::DEFAULT_DIFFICULTY_BITS);
            let _ = std::fs::write(&identity_path, k.to_protobuf_encoding().unwrap());
            k
        }
    } else {
        let k = kinetic_network::pow::mine_sybil_keypair(current_round, kinetic_network::pow::DEFAULT_DIFFICULTY_BITS);
        let _ = std::fs::write(&identity_path, k.to_protobuf_encoding().unwrap());
        k
    };

    let (bootstrap_nodes, seed_domains) = bootstrap::all_bootstrap_nodes();

    let network_config = NetworkConfig {
        mode: NetworkMode::LightClient,
        // Port 0 means the OS assigns an ephemeral port. Light clients don't
        // need a stable listen address — they only dial out.
        listen_addr: "/ip4/0.0.0.0/tcp/0".to_string(),
        external_address: None,
        bootstrap_nodes,
        seed_domains,
        initial_drand_pulse: current_round,
        enable_mdns: true,
    };

    let (drand_pulse_tx, drand_pulse_rx) = watch::channel(current_round);

    let (network_client, network_loop) = NetworkEventLoop::new(
        network_config,
        local_key,
        storage,
        drand_pulse_rx,
        None, // Light clients don't accept incoming proxy requests
    )?;

    let client = Arc::new(network_client);
    NETWORK_CLIENT
        .set(client.clone())
        .map_err(|_| anyhow::anyhow!("Network client already initialized"))?;
    let _ = TRANSPORT_BRIDGES.set(Arc::new(Mutex::new(HashMap::new())));
    let _ = BRIDGE_TOKEN.set(libp2p::identity::Keypair::generate_ed25519().public().to_peer_id().to_string());

    // Run the network event loop
    tokio::spawn(async move {
        network_loop.run().await;
    });

    // Periodically fetch fresh Drand pulses and broadcast to the network loop.
    // This replaces the previous Box::leak approach which caused the watch channel
    // to never forward new rounds, leaving the network loop stuck on the startup pulse.
    tokio::spawn(async move {
        // Drand quicknet ticks every 3 seconds; we poll every 60s to stay reasonably
        // fresh without hammering the Drand API on a mobile connection.
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        interval.tick().await; // skip the immediate first tick (we already fetched)
        loop {
            interval.tick().await;
            let new_round = fetch_latest_drand().await;
            // Only send if the round has advanced — avoids spurious wakeups.
            if new_round > *drand_pulse_tx.borrow() {
                let _ = drand_pulse_tx.send(new_round);
            }
        }
    });

    Ok(())
}

/// Returns the local HTTP port for a given peer, spawning a transport bridge
/// if one does not already exist. The Flutter WebView loads the site via
/// `http://127.0.0.1:<port>` which this bridge proxies over libp2p.
pub(crate) async fn get_or_spawn_transport_bridge(peer_id: libp2p::PeerId, fqdn: &str) -> Result<u16> {
    let peer_str = peer_id.to_string();

    let map_arc = TRANSPORT_BRIDGES
        .get()
        .ok_or_else(|| anyhow::anyhow!("TRANSPORT_BRIDGES not initialized — call init_light_client() first"))?;
    let mut map = map_arc.lock().await;

    // Check if bridge already exists
    if let Some(info) = map.get_mut(&peer_str) {
        info.last_accessed = std::time::Instant::now();
        return Ok(info.port);
    }

    // LRU eviction if we exceed 10 active bridges
    if map.len() >= 10 {
        let oldest = map.iter()
            .min_by_key(|(_, info)| info.last_accessed)
            .map(|(k, _)| k.clone());
        if let Some(old_peer) = oldest {
            if let Some(info) = map.remove(&old_peer) {
                let _ = info.shutdown_tx.send(());
            }
        }
    }

    let client = NETWORK_CLIENT
        .get()
        .ok_or_else(|| anyhow::anyhow!("NETWORK_CLIENT not initialized — call init_light_client() first"))?
        .clone();

    let app = Router::new()
        .route("/{*path}", any(handle_bridge_request))
        .route("/", any(handle_bridge_request))
        .with_state((client, peer_id, fqdn.to_string()));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();

    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel();
    map.insert(peer_str.clone(), BridgeInfo {
        port,
        last_accessed: std::time::Instant::now(),
        shutdown_tx,
    });

    let server_handle = tokio::spawn(async move {
        let server = axum::serve(listener, app).with_graceful_shutdown(async {
            shutdown_rx.await.ok();
        });
        if let Err(e) = server.await {
            eprintln!("[kinetic-ffi] Transport bridge for peer {} failed: {}", peer_id, e);
        }
    });

    let peer_str_clone = peer_str.clone();
    tokio::spawn(async move {
        let _ = server_handle.await; // Wait for server task to finish or panic
        if let Some(map_arc) = TRANSPORT_BRIDGES.get() {
            let mut map = map_arc.lock().await;
            map.remove(&peer_str_clone);
        }
    });

    Ok(port)
}

/// Backward-compatible alias — `frb_generated.rs` was code-generated calling this name.
/// It delegates to `init_light_client()` which is the canonical function.
pub async fn init_daemon(bootstrap_nodes: Vec<String>) -> anyhow::Result<()> {
    // The bootstrap_nodes argument is ignored — we always use the production
    // bootstrap list from `bootstrap.rs`. This signature is kept to avoid
    // needing to regenerate the flutter_rust_bridge bindings.
    let _ = bootstrap_nodes;
    init_light_client().await
}

/// Proxies an incoming HTTP request from the WebView to the target peer
/// over the libp2p stream multiplexer.
async fn handle_bridge_request(
    State((client, peer_id, fqdn)): State<(Arc<NetworkClient>, libp2p::PeerId, String)>,
    req: Request,
) -> Result<Response, StatusCode> {
    let method = req.method().as_str().to_string();
    let path = req
        .uri()
        .path_and_query()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| "/".to_string());

    let token = BRIDGE_TOKEN.get().cloned().unwrap_or_default();
    let mut is_authorized = false;
    
    if let Some(cookie) = req.headers().get(axum::http::header::COOKIE) {
        if cookie.to_str().unwrap_or("").contains(&format!("bridge_token={}", token)) {
            is_authorized = true;
        }
    }
    
    if !is_authorized && path.contains(&format!("bridge_token={}", token)) {
        is_authorized = true;
    }

    if !is_authorized {
        return Ok(Response::builder()
            .status(StatusCode::UNAUTHORIZED)
            .body(axum::body::Body::from("Unauthorized Kinetic Bridge Access"))
            .unwrap());
    }

    let mut headers = HashMap::new();
    for (name, value) in req.headers() {
        if let Ok(val_str) = value.to_str() {
            if name.as_str().eq_ignore_ascii_case("host") {
                headers.insert("host".to_string(), fqdn.clone());
            } else {
                headers.insert(name.as_str().to_string(), val_str.to_string());
            }
        }
    }

    let body_bytes = axum::body::to_bytes(req.into_body(), usize::MAX)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .to_vec();

    let proxy_req = kinetic_network::ProxyRequest {
        method,
        path,
        headers,
        body: body_bytes,
    };

    let proxy_resp = match client.send_proxy_request(peer_id, proxy_req).await {
        Ok(resp) => resp,
        Err(kinetic_network::client::ProxyError::Timeout) => return Err(StatusCode::GATEWAY_TIMEOUT),
        Err(kinetic_network::client::ProxyError::Offline) => return Err(StatusCode::SERVICE_UNAVAILABLE),
        Err(_) => return Err(StatusCode::BAD_GATEWAY),
    };

    let mut builder = Response::builder().status(proxy_resp.status);
    for (k, v) in proxy_resp.headers {
        builder = builder.header(k, v);
    }
    
    builder = builder.header(
        axum::http::header::SET_COOKIE,
        format!("bridge_token={}; Path=/; HttpOnly; SameSite=Strict", token)
    );
    
    // Mitigate Sandbox Escape (Edge Case 81): Prevent malicious .kin sites
    // from port-scanning localhost or the LAN.
    builder = builder.header(
        "Content-Security-Policy",
        "default-src 'self' 'unsafe-inline' 'unsafe-eval' blob: data:; connect-src 'self' wss:; frame-src 'none'; object-src 'none';"
    );

    let body = axum::body::Body::from(proxy_resp.body);
    Ok(builder
        .body(body)
        .unwrap_or_else(|_| Response::new(axum::body::Body::empty())))
}

/// Expose manual reconnect for Flutter AppLifecycleState.resumed
pub async fn reconnect_network() -> Result<()> {
    if let Some(client) = NETWORK_CLIENT.get() {
        tracing::info!("Flutter requested network reconnect/bootstrap");
        let _ = client.rebootstrap_network().await;
    }
    Ok(())
}

/// Shuts down all active transport bridges. Useful during hot-restarts
/// or memory cleanups to avoid port collisions (Case 160).
pub async fn shutdown_bridges() {
    if let Some(map_arc) = TRANSPORT_BRIDGES.get() {
        let mut map = map_arc.lock().await;
        // Drain the map and send shutdown signal to all axum servers
        for (_, info) in map.drain() {
            let _ = info.shutdown_tx.send(());
        }
    }
}

#[derive(serde::Deserialize)]
struct DrandResponse {
    round: u64,
}

pub async fn fetch_latest_drand() -> u64 {
    let drand_urls = [
        "https://api.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
        "https://drand.cloudflare.com/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
        "https://api2.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest",
        "https://api3.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest"
    ];
    
    for url in drand_urls.iter() {
        if let Ok(resp) = reqwest::get(*url).await {
            if let Ok(json) = resp.json::<DrandResponse>().await {
                return json.round;
            }
        }
    }
    
    // Offline fallback mathematically estimated from quicknet genesis
    let genesis_time = 1692803367u64;
    let round_period = 3u64;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs();
    if now > genesis_time {
        return (now - genesis_time) / round_period;
    }
    0
}
