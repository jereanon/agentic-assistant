use async_trait::async_trait;
use tokio::sync::broadcast;

use orra::hook::Hook;
use orra::namespace::Namespace;
use orra::store::Session;

/// Notifies WebSocket clients whenever a session is saved.
///
/// This hook fires on every `before_session_save` call — including
/// intermediate saves that happen after each tool-use turn in the agent
/// loop.  The notification tells the frontend to re-fetch the session so
/// that long-running tasks (cron jobs, multi-turn agent runs) show
/// incremental progress in the chat UI.
pub struct SessionNotifyHook {
    events_tx: broadcast::Sender<String>,
}

impl SessionNotifyHook {
    pub fn new(events_tx: broadcast::Sender<String>) -> Self {
        Self { events_tx }
    }
}

#[async_trait]
impl Hook for SessionNotifyHook {
    async fn before_session_save(&self, namespace: &Namespace, _session: &mut Session) {
        let key = namespace.key();
        // Only notify for web sessions — these are the ones with a
        // connected WebSocket client that can react to the event.
        if key.starts_with("web:") {
            let _ = self.events_tx.send(key);
        }
    }
}
