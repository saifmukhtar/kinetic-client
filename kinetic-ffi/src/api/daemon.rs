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

/// Maps PeerId string → local port of its dedicated Transport Bridge.
/// Each .kin site gets its own local HTTP bridge port so the WebView
/// can load it via `http://127.0.0.1:<port>`.
pub static TRANSPORT_BRIDGES: OnceCell<Arc<Mutex<HashMap<String, u16>>>> = OnceCell::const_new();

/// Initializes the Kinetic Light Client. Safe to call multiple times —
/// subsequent calls are no-ops. Uses production bootstrap nodes by default.
pub async fn init_light_client() -> Result<()> {
    if NETWORK_CLIENT.initialized() {
        return Ok(());
    }

    // Use a temporary directory for light client storage.
    // Light clients don't persist data across app launches.
    let mut base_tmp = std::env::temp_dir();
    let paths = [
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

    let temp_dir = base_tmp.join(format!(
        "kinetic_light_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("System clock error")
            .as_secs()
    ));
    std::fs::create_dir_all(&temp_dir)?;
    let storage = Arc::new(SledStorage::new(&temp_dir)?);

    // Fetch current drand pulse to mine a valid PoW for the bootstrap nodes
    #[derive(serde::Deserialize)]
    struct DrandResponse {
        round: u64,
    }
    let current_round = reqwest::get("https://api.drand.sh/52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971/public/latest")
        .await
        .map_err(|e| anyhow::anyhow!("Failed to fetch drand: {}", e))?
        .json::<DrandResponse>()
        .await
        .map_err(|e| anyhow::anyhow!("Failed to parse drand: {}", e))?
        .round;

    // Light clients now MUST mine a Sybil-resistant identity because the AWS
    // bootstrap nodes rigorously enforce PoW on all connections.
    let local_key = kinetic_network::pow::mine_sybil_keypair(current_round, kinetic_network::pow::DEFAULT_DIFFICULTY_BITS);

    let (bootstrap_nodes, seed_domains) = bootstrap::all_bootstrap_nodes();

    let network_config = NetworkConfig {
        mode: NetworkMode::LightClient,
        // Port 0 means the OS assigns an ephemeral port. Light clients don't
        // need a stable listen address — they only dial out.
        listen_addr: "/ip4/0.0.0.0/tcp/0".to_string(),
        bootstrap_nodes,
        seed_domains,
        initial_drand_pulse: current_round,
        enable_mdns: true,
    };

    let (drand_pulse_tx, drand_pulse_rx) = watch::channel(current_round);
    // Leak the sender so the watch channel stays alive for the process lifetime.
    Box::leak(Box::new(drand_pulse_tx));

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

    tokio::spawn(async move {
        network_loop.run().await;
    });

    Ok(())
}

/// Returns the local HTTP port for a given peer, spawning a transport bridge
/// if one does not already exist. The Flutter WebView loads the site via
/// `http://127.0.0.1:<port>` which this bridge proxies over libp2p.
pub(crate) async fn get_or_spawn_transport_bridge(peer_id: libp2p::PeerId) -> Result<u16> {
    let peer_str = peer_id.to_string();

    let map_arc = TRANSPORT_BRIDGES
        .get()
        .expect("TRANSPORT_BRIDGES not initialized — call init_light_client() first");
    let mut map = map_arc.lock().await;

    if let Some(&port) = map.get(&peer_str) {
        return Ok(port);
    }

    let client = NETWORK_CLIENT
        .get()
        .expect("NETWORK_CLIENT not initialized — call init_light_client() first")
        .clone();

    let app = Router::new()
        .route("/{*path}", any(handle_bridge_request))
        .route("/", any(handle_bridge_request))
        .with_state((client, peer_id));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();

    map.insert(peer_str, port);

    tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app).await {
            eprintln!("[kinetic-ffi] Transport bridge for peer {} failed: {}", peer_id, e);
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
    State((client, peer_id)): State<(Arc<NetworkClient>, libp2p::PeerId)>,
    req: Request,
) -> Result<Response, StatusCode> {
    let method = req.method().as_str().to_string();
    let path = req
        .uri()
        .path_and_query()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| "/".to_string());

    let mut headers = HashMap::new();
    for (name, value) in req.headers() {
        if let Ok(val_str) = value.to_str() {
            headers.insert(name.as_str().to_string(), val_str.to_string());
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

    let proxy_resp = client
        .send_proxy_request(peer_id, proxy_req)
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    let mut builder = Response::builder().status(proxy_resp.status);
    for (k, v) in proxy_resp.headers {
        builder = builder.header(k, v);
    }

    let body = axum::body::Body::from(proxy_resp.body);
    Ok(builder
        .body(body)
        .unwrap_or_else(|_| Response::new(axum::body::Body::empty())))
}
