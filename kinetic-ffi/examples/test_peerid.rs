use libp2p::identity::Keypair;
use std::fs;

fn main() {
    let bytes = fs::read("/home/saif/.config/kinetic/db/identity.bin").unwrap();
    let key = Keypair::from_protobuf_encoding(&bytes).unwrap();
    println!("{}", key.public().to_peer_id());
}
