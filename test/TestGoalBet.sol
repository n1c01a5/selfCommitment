pragma solidity >=0.4.25 <0.6.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/GoalBet.sol";

contract TestGoalBet {

  function testInitialBalanceUsingDeployedContract() public {
    // MetaCoin meta = MetaCoin(DeployedAddresses.MetaCoin());

    // uint expected = 10000;

    // Assert.equal(meta.getBalance(tx.origin), expected, "Owner should have 10000 MetaCoin initially");
  }
}
