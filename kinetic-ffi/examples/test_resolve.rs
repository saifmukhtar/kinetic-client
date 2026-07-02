use rust_lib_mobile::api::resolver::resolve_kin_url;
use rust_lib_mobile::api::daemon::init_light_client;
use tokio;

#[tokio::main]
async fn main() {
    println!("Initializing light client...");
    let result = init_light_client().await;
    println!("Init result: {:?}", result);

    println!("Waiting for network to connect...");
    tokio::time::sleep(std::time::Duration::from_secs(5)).await;

    println!("Resolving saif.kin...");
    let resolved = resolve_kin_url("kin://saif.kin".to_string()).await;
    println!("Resolve result: {:?}", resolved);
}
