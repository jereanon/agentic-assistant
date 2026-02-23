//! mDNS service discovery for federation.
//!
//! Registers this herald instance as `_herald._tcp.local.` and browses for
//! other instances on the local network.

use super::client::PeerClient;
use super::{PeerHealth, PeerRegistry, PeerSource, PeerState};

/// mDNS service type for herald federation.
const SERVICE_TYPE: &str = "_herald._tcp.local.";

/// Register this instance as an mDNS service.
///
/// This blocks (via mDNS daemon loop) — run in a `tokio::spawn`.
pub async fn register_service(
    instance_name: &str,
    port: u16,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mdns = mdns_sd::ServiceDaemon::new()?;

    let service_info = mdns_sd::ServiceInfo::new(
        SERVICE_TYPE,
        instance_name,
        &format!("{instance_name}.local."),
        "",
        port,
        None,
    )
    .map_err(|e| format!("failed to create service info: {e}"))?;

    mdns.register(service_info)?;

    eprintln!("[federation] mDNS: registered as '{instance_name}' on port {port}");

    // Keep the daemon alive. It runs in its own background threads.
    // We just need to hold the ServiceDaemon to keep it registered.
    // Sleep forever (the task will be cancelled on shutdown).
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
    }
}

/// Browse for peer herald instances via mDNS and update the registry.
///
/// This runs continuously — launch in a `tokio::spawn`.
pub async fn browse_peers(
    registry: PeerRegistry,
    own_instance: &str,
    global_secret: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mdns = mdns_sd::ServiceDaemon::new()?;
    let receiver = mdns.browse(SERVICE_TYPE)?;

    eprintln!("[federation] mDNS: browsing for peers...");

    let own_instance = own_instance.to_string();
    let global_secret = global_secret.to_string();

    loop {
        match receiver.recv_async().await {
            Ok(event) => match event {
                mdns_sd::ServiceEvent::ServiceResolved(info) => {
                    let peer_name = info.get_fullname().to_string();

                    // Skip our own instance
                    if peer_name.contains(&own_instance) {
                        continue;
                    }

                    // Extract the instance name from the full name
                    // Full name format: "instance._herald._tcp.local."
                    let short_name = peer_name
                        .split('.')
                        .next()
                        .unwrap_or(&peer_name)
                        .to_string();

                    let port = info.get_port();
                    let addresses = info.get_addresses();

                    if let Some(addr) = addresses.iter().next() {
                        let url = format!("http://{addr}:{port}");
                        eprintln!("[federation] mDNS: discovered peer '{short_name}' at {url}");

                        // Try to discover agents from this peer
                        match PeerClient::discover_agents(&url, &global_secret).await {
                            Ok(agents) => {
                                registry
                                    .update_peer(PeerState {
                                        name: short_name,
                                        url,
                                        shared_secret: global_secret.clone(),
                                        agents,
                                        health: PeerHealth::Healthy,
                                        source: PeerSource::Mdns,
                                    })
                                    .await;
                            }
                            Err(e) => {
                                eprintln!(
                                    "[federation] mDNS: failed to discover agents from '{peer_name}': {e}"
                                );
                                // Still register the peer so health checks can find it later
                                registry
                                    .update_peer(PeerState {
                                        name: short_name,
                                        url,
                                        shared_secret: global_secret.clone(),
                                        agents: vec![],
                                        health: PeerHealth::Unknown,
                                        source: PeerSource::Mdns,
                                    })
                                    .await;
                            }
                        }
                    }
                }
                mdns_sd::ServiceEvent::ServiceRemoved(_, fullname) => {
                    let short_name = fullname.split('.').next().unwrap_or(&fullname).to_string();

                    // Only remove mDNS-discovered peers, not static ones
                    let peers = registry.list_peers().await;
                    if let Some(peer) = peers.iter().find(|p| p.name == short_name) {
                        if peer.source == PeerSource::Mdns {
                            eprintln!("[federation] mDNS: peer '{short_name}' removed");
                            registry.remove_peer(&short_name).await;
                        }
                    }
                }
                _ => {
                    // SearchStarted, SearchStopped, etc. — ignore
                }
            },
            Err(e) => {
                eprintln!("[federation] mDNS browse error: {e}");
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
        }
    }
}
