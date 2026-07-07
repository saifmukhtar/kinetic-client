#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_resolve() {
        crate::api::daemon::init_light_client().await.unwrap();
        let doc = crate::api::resolver::resolve_kin_url(format!("letsgoitsanewkineticdomain{}", kinetic_core::types::DOT_TLD).to_string()).await;
        println!("Resolve result: {:?}", doc);
    }
}
