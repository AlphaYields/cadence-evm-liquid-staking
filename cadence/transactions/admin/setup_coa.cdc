import "EVM"

/// Creates a Cadence Owned Account (COA) and stores it in the signer's storage.
/// The COA acts as the owner of all EVM contracts deployed by the protocol.
transaction {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        if signer.storage.type(at: /storage/evm) != nil {
            log("COA already exists")
            return
        }

        let coa <- EVM.createCadenceOwnedAccount()
        log("COA created at EVM address: ".concat(coa.address().toString()))
        signer.storage.save(<-coa, to: /storage/evm)
    }
}
