import "stFlowToken"

/// Returns the Cadence type identifier for `@stFlowToken.Vault` on the **current import mapping** (use the same
/// network as `flow.json` / CLI `-n`). Pass to keeper bridge args (`vaultIdentifier`).
access(all) fun main(): String {
    return Type<@stFlowToken.Vault>().identifier
}
