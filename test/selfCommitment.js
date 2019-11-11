const SelfCommitment = artifacts.require("SelfCommitment")
const ArbitrableBetList = artifacts.require("ArbitrableBetList")
const truffleAssert = require('truffle-assertions')
const AppealableArbitrator = artifacts.require(
  'AppealableArbitrator.sol'
)
const EnhancedAppealableArbitrator = artifacts.require(
  'EnhancedAppealableArbitrator.sol'
)

/* NOTE: The time management is quite chaotic.
I assume the test coverage is very low. PRs are welcome! */

const timeout = ms => new Promise(resolve => setTimeout(resolve, ms))

contract('SelfCommitment', (accounts) => {
  const governor = accounts[0]
  const asker = accounts[1]
  const taker = accounts[2]
  const arbitratorExtraData = "0x0"
  const baseDeposit = 10 ** 10
  const arbitrationCost = "1000"
  const sharedStakeMultiplier = "10000"
  const winnerStakeMultiplier = "20000"
  const loserStakeMultiplier = 2 * winnerStakeMultiplier
  const challengePeriodDuration = "5"
  const registrationMetaEvidence = 'registrationMetaEvidence.json'
  const clearingMetaEvidence = 'clearingMetaEvidence.json'
  const appealPeriodDuration = "1001"

  let appealableArbitrator
  let enhancedAppealableArbitrator
  let arbitrableBetList
  let MULTIPLIER_DIVISOR


  const deployArbitrators = async () => {
    appealableArbitrator = await AppealableArbitrator.new(
      arbitrationCost, // _arbitrationCost
      governor, // _arbitrator
      arbitratorExtraData, // _arbitratorExtraData
      appealPeriodDuration // _appealPeriodDuration
    )
    await appealableArbitrator.changeArbitrator(appealableArbitrator.address)

    enhancedAppealableArbitrator = await EnhancedAppealableArbitrator.new(
      arbitrationCost, // _arbitrationCost
      governor, // _arbitrator
      arbitratorExtraData, // _arbitratorExtraData
      appealPeriodDuration, // _timeOut
      {
        from: governor
      }
    )

    await enhancedAppealableArbitrator.changeArbitrator(
      enhancedAppealableArbitrator.address
    )
  }

  const deployArbitrableBetList = async arbitrator => {
    arbitrableBetList = await ArbitrableBetList.new(
      arbitrator.address,
      arbitratorExtraData,
      registrationMetaEvidence,
      clearingMetaEvidence,
      governor,
      baseDeposit,
      baseDeposit,
      challengePeriodDuration,
      sharedStakeMultiplier,
      winnerStakeMultiplier,
      loserStakeMultiplier,
      {
        from: governor,
        gasPrice: "100000000000" // 100 Shannon
      }
    )

    MULTIPLIER_DIVISOR = await arbitrableBetList.MULTIPLIER_DIVISOR()
  }

  describe('bet flow', () => {
    beforeEach(async () => {
      await deployArbitrators()
      await deployArbitrableBetList(enhancedAppealableArbitrator)
    })

    it('should bet 2:1, take and claim', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const initialBalanceAcc1 = await web3.eth.getBalance(accounts[3])

      const endBetPeriod = Math.floor((Date.now() + 100) / 1000) + 2
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 3
      const endClaimEndPeriod = Math.floor(Date.now() / 1000) + 6

      const tx0Receipt = await selfCommitmentInstance.ask(
        "_description",
        [
          endBetPeriod.toString(),
          startClaimPeriod.toString(),
          endClaimEndPeriod.toString()
        ],
        ["2", "1"],
        [],
        enhancedAppealableArbitrator.address.toString(),
        "0x0",
        [1,1,1],
        {
          from: accounts[3],
          value: web3.utils.toBN("100000000000000").add(web3.utils.toBN("10000002000")).toString(), // 100000000000000 Wei + totalCost
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx0 receipt
      const gasUsedTx0 = web3.utils.toBN(await tx0Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc1AfterTx0 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      const txCost = gasUsedTx0.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        (
          balanceAcc1AfterTx0.add(
            web3.utils.toBN("100000000000000")
          ).add(
            web3.utils.toBN("10000002000")
          ).add(
            txCost
          )
        ).toString(),
        initialBalanceAcc1.toString(),
        "Must be equal (tx0)"
      )

      /******************************* Take tx *******************************/
      const initialBalanceAcc2 = await web3.eth.getBalance(accounts[2])

      const maxAmountToBet = await selfCommitmentInstance.getMaxAmountToBet.call(
        "0"
      )

      assert.equal(
        maxAmountToBet.toString(),
        "100000000000000",
        "MaxAmountToBet must be 100000000000000 Wei"
      )

      const tx1Receipt = await selfCommitmentInstance.take(
        "0",
        {
          from: taker,
          value: "100000000000000",
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx1 receipt
      const gasUsedTx1 = web3.utils.toBN(tx1Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc2AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[2]))

      const tx1Cost = gasUsedTx1.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        (balanceAcc2AfterTx1.add(tx1Cost).add(web3.utils.toBN("100000000000000"))).toString(),
        initialBalanceAcc2.toString(),
        "Must be equal (tx1)"
      )

      /******************************* Claim tx *******************************/
      // Balance after tx1
      const balanceAcc1AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      // Wait 3s for the bet period end
      await timeout(4000)

      const claimCost = web3.utils.toBN(
        await selfCommitmentInstance.getClaimCost.call(
          "0"
        )
      )

      assert.equal(claimCost.toString(), "1000", "Must be 1000wei")

      const tx2Receipt = await selfCommitmentInstance.claimAsker(
        "0",
        {
          value: "1000",
          gasPrice: "100000000000",
          from: accounts[3]
        }
      )

      // Obtain gas used from the tx2 receipt
      const gasUsedTx2 = web3.utils.toBN(tx2Receipt.receipt.gasUsed)
      const tx2Cost = gasUsedTx2.mul(web3.utils.toBN('100000000000'))

      // Balance after tx2
      const balanceAcc1AfterTx2 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      assert.equal(
        balanceAcc1AfterTx1.toString(),
        balanceAcc1AfterTx2.add(tx2Cost).add(web3.utils.toBN("1000")).toString(),
        "Must be equal (tx2)"
      )

      // Wait 3s for the bet period end
      await timeout(3000)

      await selfCommitmentInstance.timeOutByAsker(
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      // Balance after tx3
      const balanceAcc1AfterTx3 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      assert.equal(
        balanceAcc1AfterTx2.add(web3.utils.toBN("200000000000000")).add(web3.utils.toBN("1000")).toString(),
        balanceAcc1AfterTx3.toString(),
        "Must be equal (tx3)"
      )

      const contractBalance = web3.utils.toBN(await web3.eth.getBalance(selfCommitmentInstance.address))

      assert.equal(
        contractBalance.toString(),
        "0",
        "Must be 0."
      )
    })

    it('should bet and withdraw after the period bet end', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const initialBalanceAcc1 = web3.utils.toBN(await web3.eth.getBalance(accounts[8]))

      const endBetPeriod = Math.floor(Date.now() / 1000) + 1
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 2
      const endClaimEndPeriod = Math.floor(Date.now() / 1000) + 4

      const tx0Receipt = await selfCommitmentInstance.ask(
        "_description",
        [
          endBetPeriod.toString(),
          startClaimPeriod.toString(),
          endClaimEndPeriod.toString()
        ],
        ["2", "1"],
        [],
        enhancedAppealableArbitrator.address.toString(),
        "0x0",
        [1,1,1],
        {
          from: accounts[8],
          value: web3.utils.toBN("10000000000000000000").add(web3.utils.toBN("10000002000")).toString(), // 1 ether + totalCost
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx0 receipt
      const gasUsedTx0 = web3.utils.toBN(tx0Receipt.receipt.gasUsed)

      // Obtain gasPrice from the transaction
      const tx0Cost = gasUsedTx0.mul(web3.utils.toBN("100000000000"))

      // Balance after tx0
      const balanceAcc1AfterTx0 = web3.utils.toBN(await web3.eth.getBalance(accounts[8]))

      assert.equal(
        balanceAcc1AfterTx0.add(tx0Cost).add(web3.utils.toBN("10000000000000000000")).add(web3.utils.toBN("10000002000")).toString(),
        initialBalanceAcc1.toString(),
        "Must be equal (tx0)"
      )

      /******************************* Withdraw tx *******************************/
      // Wait 3s for the bet period end
      await timeout(3000)

      await selfCommitmentInstance.withdraw(
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      // Balance after tx1
      const balanceAcc1AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[8]))

      // Acc1 must increase his balance of 1 ether
      assert.equal(
        balanceAcc1AfterTx1.toString(),
        balanceAcc1AfterTx0.add(web3.utils.toBN("10000000000000000000")).toString(),
        "Must be equal (tx1)"
      )

      // TODO: withdraw arbitrableBetList deposit
    })

    it('should bet, partial take and withdraw the rest by asker after the bet period (ratio 2:1)', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const initialBalanceAcc1 = await web3.eth.getBalance(accounts[3])

      const endBetPeriod = Math.floor((Date.now() + 100) / 1000) + 2
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 3
      const endClaimEndPeriod = Math.floor(Date.now() / 1000) + 6

      const tx0Receipt = await selfCommitmentInstance.ask(
        "_description",
        [
          endBetPeriod.toString(),
          startClaimPeriod.toString(),
          endClaimEndPeriod.toString()
        ],
        ["2", "1"],
        [],
        enhancedAppealableArbitrator.address.toString(),
        "0x0",
        [1,1,1],
        {
          from: accounts[3],
          value: web3.utils.toBN("10000000000000000000").add(web3.utils.toBN("10000002000")).toString(), // 1 ether + totalCost
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx0 receipt
      const gasUsedTx0 = web3.utils.toBN(await tx0Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc1AfterTx0 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      const txCost = gasUsedTx0.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        (
          balanceAcc1AfterTx0.add(
            web3.utils.toBN("10000000000000000000")
          ).add(
            web3.utils.toBN("10000002000")
          ).add(
            txCost
          )
        ).toString(),
        initialBalanceAcc1.toString(),
        "Must be equal (tx0)"
      )

      /******************************* Partial Take tx *******************************/
      const initialBalanceAcc2 = await web3.eth.getBalance(accounts[2])

      const maxAmountToBet = await selfCommitmentInstance.getMaxAmountToBet.call(
        "0"
      )

      assert.equal(
        maxAmountToBet.toString(),
        "10000000000000000000",
        "MaxAmountToBet must be 1 ether"
      )

      const tx1Receipt = await selfCommitmentInstance.take(
        "0",
        {
          from: accounts[2],
          value: "5000000000000000000",
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx1 receipt
      const gasUsedTx1 = web3.utils.toBN(tx1Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc2AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[2]))

      const tx1Cost = gasUsedTx1.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        balanceAcc2AfterTx1.add(tx1Cost).add(web3.utils.toBN("5000000000000000000")).toString(),
        initialBalanceAcc2.toString(),
        "Must be equal (tx1)"
      )

      /******************************* Partial withdraw tx *******************************/
      // Wait 5s for the bet period end
      await timeout(5000)

      await selfCommitmentInstance.withdraw(
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      // Balance after tx1
      const balanceAcc1AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      // Acc1 must increase his balance of 0.5 ether
      assert.equal(
        balanceAcc1AfterTx1.toString(),
        balanceAcc1AfterTx0.add(web3.utils.toBN("5000000000000000000")).toString(),
        "Must be equal (tx1)"
      )
    })

    it('should bet, partial take and withdraw the rest by asker after the bet period (ratio 10:1)', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const initialBalanceAcc1 = await web3.eth.getBalance(accounts[3])

      const endBetPeriod = Math.floor((Date.now() + 100) / 1000) + 2
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 3
      const endClaimEndPeriod = Math.floor(Date.now() / 1000) + 6

      const tx0Receipt = await selfCommitmentInstance.ask(
        "_description",
        [
          endBetPeriod.toString(),
          startClaimPeriod.toString(),
          endClaimEndPeriod.toString()
        ],
        ["10", "1"],
        [],
        enhancedAppealableArbitrator.address.toString(),
        "0x0",
        [1,1,1],
        {
          from: accounts[3],
          value: web3.utils.toBN("9000000000000000000").add(web3.utils.toBN("10000002000")).toString(), // 0.9 ether + totalCost
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx0 receipt
      const gasUsedTx0 = web3.utils.toBN(await tx0Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc1AfterTx0 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      const txCost = gasUsedTx0.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        (
          balanceAcc1AfterTx0.add(
            web3.utils.toBN("9000000000000000000")
          ).add(
            web3.utils.toBN("10000002000")
          ).add(
            txCost
          )
        ).toString(),
        initialBalanceAcc1.toString(),
        "Must be equal (tx0)"
      )

      /******************************* Partial Take tx *******************************/
      const initialBalanceAcc2 = await web3.eth.getBalance(accounts[2])

      const maxAmountToBet = await selfCommitmentInstance.getMaxAmountToBet.call(
        "0"
      )

      assert.equal(
        maxAmountToBet.toString(),
        "1000000000000000000",
        "MaxAmountToBet must be 0.1 ether"
      )

      const tx1Receipt = await selfCommitmentInstance.take(
        "0",
        {
          from: accounts[2],
          value: "100000000000000000", // 0.01 Ether
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx1 receipt
      const gasUsedTx1 = web3.utils.toBN(tx1Receipt.receipt.gasUsed)

      // Balance after tx0
      const balanceAcc2AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[2]))

      const tx1Cost = gasUsedTx1.mul(web3.utils.toBN("100000000000"))

      assert.equal(
        balanceAcc2AfterTx1.add(tx1Cost).add(web3.utils.toBN("100000000000000000")).toString(),
        initialBalanceAcc2.toString(),
        "Must be equal (tx1)"
      )

      /******************************* Partial withdraw tx *******************************/
      // Wait 5s for the bet period end
      await timeout(5000)

      // Balance after tx2
      const balanceAcc1AfterTx2 = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      await selfCommitmentInstance.withdraw(
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      // Balance after withdraw
      const balanceAcc1AfterWithdraw = web3.utils.toBN(await web3.eth.getBalance(accounts[3]))

      // Acc1 must increase his balance of 8.1 ether
      assert.equal(
        balanceAcc1AfterWithdraw.toString(),
        balanceAcc1AfterTx0.add(web3.utils.toBN("8100000000000000000")).toString(),
        "Must be equal (tx3)"
      )
    })

    it('should bet revert if the ratio[1] > ratio[0]', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const endBetPeriod = Math.floor(Date.now() / 1000) + 60
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 120
      const endClaimendPeriod = Math.floor(Date.now() / 1000) + 180

      await truffleAssert.fails(
        selfCommitmentInstance.ask(
          "_description",
          [
            endBetPeriod.toString(),
            startClaimPeriod.toString(),
            endClaimendPeriod.toString()
          ],
          ["42", "101"],
          [],
          arbitrableBetList.address.toString(),
          "0x0",
          [0,0,0],
          {
            from: accounts[1],
            value: web3.utils.toBN("10000000000000000000").add(web3.utils.toBN("10000002000")).toString(), // 1 Ether + totalCost
            gasPrice: "100000000000"
          }
        ),
        truffleAssert.ErrorType.REVERT
      )
    })

    it('should bet, multiple takes and claim takers', async () => {
      const selfCommitmentInstance = await SelfCommitment.new(governor)

      await arbitrableBetList.changeSelfCommitmentRegistry(selfCommitmentInstance.address)
      await selfCommitmentInstance.changeArbitrationBetList(arbitrableBetList.address)

      /******************************* Bet tx *******************************/
      const initialBalanceAcc1 = web3.utils.toBN(await web3.eth.getBalance(accounts[5]))

      const endBetPeriod = Math.floor(Date.now() / 1000) + 2
      const startClaimPeriod = Math.floor(Date.now() / 1000) + 3
      const endClaimEndPeriod = Math.floor(Date.now() / 1000) + 6

      const tx0Receipt = await selfCommitmentInstance.ask(
        "_description",
        [
          endBetPeriod.toString(),
          startClaimPeriod.toString(),
          endClaimEndPeriod.toString()
        ],
        ["2", "1"],
        [],
        enhancedAppealableArbitrator.address.toString(),
        "0x0",
        [1,1,1],
        {
          from: accounts[5],
          value: web3.utils.toBN("10000000000000000000").add(web3.utils.toBN("10000002000")).toString(), // 1 Ether + totalCost
          gasPrice: "100000000000" // 100 Shannon
        }
      )

      // Obtain gas used from the tx0 receipt
      const gasUsedTx0 = web3.utils.toBN(tx0Receipt.receipt.gasUsed)

      // Obtain gasPrice from the transaction
      const tx0Cost = gasUsedTx0.mul(web3.utils.toBN("100000000000"))

      // Balance after tx0
      const balanceAcc1AfterTx0 = web3.utils.toBN(await web3.eth.getBalance(accounts[5]))

      assert.equal(
        balanceAcc1AfterTx0.add(tx0Cost).add(web3.utils.toBN("10000000000000000000")).add(web3.utils.toBN("10000002000")).toString(),
        initialBalanceAcc1.toString(),
        "Must be equal (tx0)"
      )

      /******************************* Take 1 tx *******************************/
      const initialBalanceAcc2 = web3.utils.toBN(await web3.eth.getBalance(accounts[6]))

      const tx1Receipt = await selfCommitmentInstance.take(
        "0",
        {
          from: accounts[6],
          value: "5000000000000000000",
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx1 receipt
      const gasUsedTx1 = web3.utils.toBN(tx1Receipt.receipt.gasUsed)

      // Obtain gasPrice from the transaction
      const tx1Cost = gasUsedTx1.mul(web3.utils.toBN("100000000000"))

      // Balance after tx1
      const balanceAcc2AfterTx1 = web3.utils.toBN(await web3.eth.getBalance(accounts[6]))

      assert.equal(
        balanceAcc2AfterTx1.add(tx1Cost).add(web3.utils.toBN("5000000000000000000")).toString(),
        initialBalanceAcc2.toString(),
        "Must be equal (tx1)"
      )

      /******************************* Take 2 tx *******************************/
      const initialBalanceAcc3 = web3.utils.toBN(await web3.eth.getBalance(accounts[7]))

      const maxAmountToBet = await selfCommitmentInstance.getMaxAmountToBet.call(
        "0"
      )

      assert.equal(
        maxAmountToBet.toString(),
        "5000000000000000000",  // 0.5 ether
        "MaxAmountToBet must be 0.5 ether"
      )

      const tx2Receipt = await selfCommitmentInstance.take(
        "0",
        {
          from: accounts[7],
          value: "2500000000000000000",
          gasPrice: "100000000000"
        }
      )

      // Obtain gas used from the tx2 receipt
      const gasUsedTx2 = web3.utils.toBN(tx2Receipt.receipt.gasUsed)

      // Obtain gasPrice from the transaction
      const tx2Cost = gasUsedTx2.mul(web3.utils.toBN("100000000000"))

      // Balance after tx2
      const balanceAcc3AfterTx2 = web3.utils.toBN(await web3.eth.getBalance(accounts[7]))

      assert.equal(
        balanceAcc3AfterTx2.add(tx2Cost).add(web3.utils.toBN("2500000000000000000")).toString(),
        initialBalanceAcc3.toString(),
        "Must be equal (tx2)"
      )

      /******************************* Claim tx *******************************/
      // Wait 4s for the bet period end
      await timeout(4500)

      const tx3Receipt = await selfCommitmentInstance.claimTaker(
        "0",
        {
          value: "1000",
          gasPrice: "100000000000",
          from: accounts[7]
        }
      )

      // Obtain gas used from the tx3 receipt.
      const gasUsedTx3 = web3.utils.toBN(tx3Receipt.receipt.gasUsed)

      // Obtain gasPrice from the transaction.
      const tx3Cost = gasUsedTx3.mul(web3.utils.toBN("100000000000"))

      // Balance after tx3.
      const balanceAcc3AfterTx3 = web3.utils.toBN(await web3.eth.getBalance(accounts[7]))

      assert.equal(
        balanceAcc3AfterTx3.add(tx3Cost).add(web3.utils.toBN("1000")).toString(),
        balanceAcc3AfterTx2.toString(),
        "Must be equal (tx3)"
      )

      // Wait 4s for the bet period end.
      await timeout(4000)

      await selfCommitmentInstance.timeOutByTaker(
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      await selfCommitmentInstance.withdrawFeesAndRewards(
        accounts[7],
        "0",
        "0",
        {
          value: "0",
          gasPrice: "100000000000"
        }
      )

      const balanceAcc3AfterTimeOutByAsker = web3.utils.toBN(await web3.eth.getBalance(accounts[7]))

      assert.equal(
        balanceAcc3AfterTimeOutByAsker.toString(),
        balanceAcc3AfterTx3.add(web3.utils.toBN("5000000000000000000")).add(web3.utils.toBN("1000")).toString(),
        "Must be equal (tx4)"
      )
    })
  })
})