import Test
import "FungibleToken"
import "FlowToken"

access(all) let deployer = Test.getAccount(0x0000000000000007)
access(all) let staker = Test.createAccount()

access(all) fun setup() {
    var err = Test.deployContract(
        name: "stFlowToken",
        path: "../contracts/stFlowToken.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    err = Test.deployContract(
        name: "LiquidStaking",
        path: "../contracts/LiquidStaking.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testContractsDeployed() {
    let priceResult = Test.executeScript(
        "import LiquidStaking from 0x0000000000000007; access(all) fun main(): UFix64 { return LiquidStaking.flowPerStFlow() }",
        []
    )
    Test.expect(priceResult, Test.beSucceeded())
    let price = priceResult.returnValue! as! UFix64
    Test.assertEqual(1.0, price)
}

access(all) fun testInitialState() {
    let tvlResult = Test.executeScript(
        "import LiquidStaking from 0x0000000000000007; import stFlowToken from 0x0000000000000007; access(all) fun main(): [UFix64; 3] { return [LiquidStaking.totalFlowStaked, stFlowToken.totalSupply, LiquidStaking.protocolFeePercent] }",
        []
    )
    Test.expect(tvlResult, Test.beSucceeded())
    let tvl = tvlResult.returnValue! as! [UFix64; 3]
    Test.assertEqual(0.0, tvl[0])
    Test.assertEqual(0.0, tvl[1])
    Test.assertEqual(0.1, tvl[2])
}

access(all) fun testPriceStartsAtOne() {
    let result = Test.executeScript(
        "import LiquidStaking from 0x0000000000000007; access(all) fun main(): [UFix64; 2] { return [LiquidStaking.flowPerStFlow(), LiquidStaking.stFlowPerFlow()] }",
        []
    )
    Test.expect(result, Test.beSucceeded())
    let prices = result.returnValue! as! [UFix64; 2]
    Test.assertEqual(1.0, prices[0])
    Test.assertEqual(1.0, prices[1])
}
