use rust_lib_mobile::api::resolver::resolve_kin_url;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    println!("Initializing and resolving...");
    
    // Give the network 5 seconds to bootstrap and identify peers
    println!("Waiting for DHT to bootstrap...");
    tokio::time::sleep(std::time::Duration::from_secs(5)).await;

    // Resolve the kin URL
    let doc = resolve_kin_url(format!("letsgoitsanewkineticdomain{}", kinetic_core::types::DOT_TLD).to_string()).await?;
    
    println!("Resolved Document:");
    println!("Raw JSON: {}", doc.raw_json);
    println!("Target URL: {:?}", doc.target_url);
    
    Ok(())
}
