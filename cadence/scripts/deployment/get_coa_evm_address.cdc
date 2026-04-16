import "EVM"

/// Reads the COA Flow EVM address for an account that ran **`admin/setup_coa.cdc`** (public cap at `/public/coaEVM`).
access(all) fun main(deployer: Address): String {
    let acct = getAccount(deployer)
    let coa = acct.capabilities.borrow<&EVM.CadenceOwnedAccount>(/public/coaEVM)
        ?? panic("Missing /public/coaEVM — run cadence/transactions/admin/setup_coa.cdc on this account")
    return coa.address().toString()
}
