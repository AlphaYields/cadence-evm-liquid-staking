import "EVM"

/// Deploys an EVM contract via the COA. Pass the compiled bytecode as hex and
/// the constructor arguments already ABI-encoded into the bytecode.
/// Returns the deployed contract address in the transaction log.
transaction(bytecodeHex: String) {
    let coa: auth(EVM.Deploy) &EVM.CadenceOwnedAccount

    prepare(signer: auth(BorrowValue) &Account) {
        self.coa = signer.storage
            .borrow<auth(EVM.Deploy) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found — run setup_coa first")
    }

    execute {
        let result = self.coa.deploy(
            code: bytecodeHex.decodeHex(),
            gasLimit: 15_000_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(result.status == EVM.Status.successful, message: "EVM deploy failed")
        log("Contract deployed at: ".concat(result.deployedContract!.toString()))
    }
}
