//! Remote delegation tool — allows agents to delegate tasks to remote peers.

use async_trait::async_trait;
use orra::channels::federation::RelayRequest;
use orra::tool::{Tool, ToolDefinition, ToolError};

use super::client::PeerClient;
use super::PeerRegistry;

/// Tool that lets an agent delegate a task to a remote agent on a federated peer.
///
/// Follows the same pattern as `DelegateToAgentTool` but routes across instances.
pub struct DelegateToRemoteAgentTool {
    /// The peer registry to look up remote agents.
    registry: PeerRegistry,
    /// Instance name of the local herald (used as source_peer in relay requests).
    instance_name: String,
    /// Name of the agent that owns this tool (for source_agent in relay).
    self_agent: String,
}

impl DelegateToRemoteAgentTool {
    pub fn new(registry: PeerRegistry, instance_name: String, self_agent: String) -> Self {
        Self {
            registry,
            instance_name,
            self_agent,
        }
    }
}

#[async_trait]
impl Tool for DelegateToRemoteAgentTool {
    fn definition(&self) -> ToolDefinition {
        ToolDefinition {
            name: "delegate_to_remote_agent".into(),
            description: "Delegate a task to an agent on a remote federated herald instance. \
                          Use this when a remote agent is better suited for a task. \
                          The target can be specified as just the agent name (searched across \
                          all peers) or as 'peer:agent' for a specific instance."
                .into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "Target agent. Can be 'agent_name' (search all peers) or 'peer:agent_name' (specific peer)"
                    },
                    "task": {
                        "type": "string",
                        "description": "The task or question to delegate to the remote agent"
                    }
                },
                "required": ["target", "task"]
            }),
        }
    }

    async fn execute(&self, input: serde_json::Value) -> Result<String, ToolError> {
        let target = input
            .get("target")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ToolError::InvalidInput("missing 'target'".into()))?;

        let task = input
            .get("task")
            .and_then(|v| v.as_str())
            .ok_or_else(|| ToolError::InvalidInput("missing 'task'".into()))?;

        // Parse target: "peer:agent" or just "agent"
        let (peer, agent_name) = if let Some((p, a)) = target.split_once(':') {
            (Some(p), a)
        } else {
            (None, target)
        };

        // Look up the remote agent
        let (url, secret, info) = self
            .registry
            .find_agent(peer, agent_name)
            .await
            .ok_or_else(|| {
                let available = tokio::task::block_in_place(|| {
                    tokio::runtime::Handle::current().block_on(async {
                        let agents = self.registry.remote_agents().await;
                        agents
                            .iter()
                            .map(|a| format!("{}:{}", a.instance, a.name))
                            .collect::<Vec<_>>()
                            .join(", ")
                    })
                });

                ToolError::ExecutionFailed(format!(
                    "remote agent '{}' not found. Available remote agents: {}",
                    target,
                    if available.is_empty() {
                        "none".to_string()
                    } else {
                        available
                    }
                ))
            })?;

        // Create the relay request
        let request = RelayRequest {
            agent: info.name.clone(),
            message: task.to_string(),
            source_peer: self.instance_name.clone(),
            source_agent: Some(self.self_agent.clone()),
            namespace: format!("federation:{}:{}", self.instance_name, uuid::Uuid::new_v4()),
        };

        // Send the relay request
        let response = PeerClient::relay_message(&url, &secret, &request)
            .await
            .map_err(|e| {
                ToolError::ExecutionFailed(format!(
                    "relay to remote agent '{}' on '{}' failed: {e}",
                    info.name, info.instance
                ))
            })?;

        Ok(format!(
            "[Remote agent '{}' on '{}' responded]\n\n{}",
            response.agent, response.instance, response.message,
        ))
    }
}
