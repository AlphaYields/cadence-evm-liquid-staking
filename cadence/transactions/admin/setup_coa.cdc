import "EVM"

/// Creates a Cadence Owned Account (COA) at `/storage/evm` and publishes a **read-only** capability at
/// **`/public/coaEVM`** so scripts (and operators filling `deployment/deployment.local.json`) can read the COA’s
/// Flow EVM address without signing keys.
transaction {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        let publicPath = /public/coaEVM

        if signer.storage.type(at: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            log("COA created at EVM address: ".concat(coa.address().toString()))
            signer.storage.save(<-coa, to: /storage/evm)
        } else {
            log("COA already exists at /storage/evm")
        }

        if signer.capabilities.borrow<&EVM.CadenceOwnedAccount>(publicPath) == nil {
            let cap = signer.capabilities.storage.issue<&EVM.CadenceOwnedAccount>(/storage/evm)
            signer.capabilities.publish(cap, at: publicPath)
            log("Published read-only COA capability at /public/coaEVM")
        }
    }
}
