import Test

access(all) fun setup() {
    let err = Test.deployContract(
        name: "stFlowToken",
        path: "../contracts/stFlowToken.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testContractDeployed() {
    assert(true)
}
