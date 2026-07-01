/// Bootstrap configuration for the Kinetic Light Client.
///
/// This module is the single source of truth for how the mobile client
/// discovers the Kinetic network. It mirrors the bootstrap strategy used
/// by `kinetic-daemon/src/config.rs`:
///
///   1. Hardcoded IP multiaddrs — fast, censorship-resistant, always available
///   2. Web2 DNS seed domain lookup — flexible, allows new nodes to be added
///      without shipping an app update
///
/// Both methods are used together so that if the AWS IPs ever change, the
/// DNS seed discovery will find the new nodes automatically.

/// Returns the hardcoded production bootstrap nodes.
/// These are the same multiaddrs as in `kinetic-daemon/src/config.rs`.
pub fn production_bootstrap_nodes() -> Vec<String> {
    vec![
        "/ip4/44.219.188.204/tcp/6070/p2p/12D3KooWJkn8Dgb33N2p9sLBNX9Eg8W8whgdjLs2YJxWuTme7ZSs"
            .to_string(),
        "/ip4/44.219.155.172/tcp/6070/p2p/12D3KooWMrtadRYuXxSgQaNJ2PyXqWTamJmEeMvCHbstczbKu69D"
            .to_string(),
        "/ip4/100.60.156.241/tcp/6070/p2p/12D3KooWRTeUzuRyiwhoxoMD14r7C2jyem5agpmzrVvcnnSDVNsc"
            .to_string(),
    ]
}

/// Returns the Web2 DNS seed domains.
/// The network layer resolves these to multiaddrs via DNS TXT records
/// (same as `kinetic-daemon`'s `seed_domains` config field).
pub fn seed_domains() -> Vec<String> {
    // Disabled on mobile to prevent DNS Wi-Fi Spoofing (Edge Case #78).
    // std::net::ToSocketAddrs uses unencrypted UDP DNS which can be intercepted by public Wi-Fi.
    // We rely exclusively on the hardcoded IP bootstrap nodes since they contain cryptographically
    // verified PeerIds (e.g. /p2p/12D3K...) which cannot be MITM'd.
    vec![]
}

/// Returns all bootstrap nodes — hardcoded IPs plus any discovered via DNS.
/// This is the function used by `daemon.rs` when initializing the light client.
///
/// DNS resolution is handled by the `kinetic-network` event loop itself
/// (it reads `seed_domains` from `NetworkConfig`), so we just return both
/// lists here for config construction.
pub fn all_bootstrap_nodes() -> (Vec<String>, Vec<String>) {
    (production_bootstrap_nodes(), seed_domains())
}
