pragma solidity >=0.4.18 <0.6.0;

/* NOTE: @kleros/kleros-interraction is not compatible with this solc version */
/* NOTE: I put all the arbitration files in the same file because the dependancy between the different contracts is a real "headache" */
/* If someone takes up the challenge, a PR is welcome */

/**
 * @title CappedMath
 * @dev Math operations with caps for under and overflow.
 * NOTE: see https://raw.githubusercontent.com/kleros/kleros-interaction/master/contracts/libraries/CappedMath.sol
 */
library CappedMath {
  uint constant private UINT_MAX = 2**256 - 1;

  /**
    * @dev Adds two unsigned integers, returns 2^256 - 1 on overflow.
    */
  function addCap(uint _a, uint _b) internal pure returns (uint) {
    uint c = _a + _b;
    return c >= _a ? c : UINT_MAX;
  }

  /**
    * @dev Subtracts two integers, returns 0 on underflow.
    */
  function subCap(uint _a, uint _b) internal pure returns (uint) {
    if (_b > _a)
      return 0;
    else
      return _a - _b;
  }

  /**
    * @dev Multiplies two unsigned integers, returns 2^256 - 1 on overflow.
    */
  function mulCap(uint _a, uint _b) internal pure returns (uint) {
    // Gas optimization: this is cheaper than requiring '_a' not being zero, but the
    // benefit is lost if '_b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (_a == 0)
      return 0;

    uint c = _a * _b;

    return c / _a == _b ? c : UINT_MAX;
  }
}

/** @title IArbitrable
 *  Arbitrable interface.
 *  When developing arbitrable contracts, we need to:
 *  -Define the action taken when a ruling is received by the contract. We should do so in executeRuling.
 *  -Allow dispute creation. For this a function must:
 *      -Call arbitrator.createDispute.value(_fee)(_choices,_extraData);
 *      -Create the event Dispute(_arbitrator,_disputeID,_rulingOptions);
 */
interface IArbitrable {
  /** @dev To be emmited when meta-evidence is submitted.
    *  @param _metaEvidenceID Unique identifier of meta-evidence.
    *  @param _evidence A link to the meta-evidence JSON.
    */
  event MetaEvidence(uint indexed _metaEvidenceID, string _evidence);

  /** @dev To be emmited when a dispute is created to link the correct meta-evidence to the disputeID
    *  @param _arbitrator The arbitrator of the contract.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _metaEvidenceID Unique identifier of meta-evidence.
    *  @param _evidenceGroupID Unique identifier of the evidence group that is linked to this dispute.
    */
  event Dispute(Arbitrator indexed _arbitrator, uint indexed _disputeID, uint _metaEvidenceID, uint _evidenceGroupID);

  /** @dev To be raised when evidence are submitted. Should point to the ressource (evidences are not to be stored on chain due to gas considerations).
    *  @param _arbitrator The arbitrator of the contract.
    *  @param _evidenceGroupID Unique identifier of the evidence group the evidence belongs to.
    *  @param _party The address of the party submiting the evidence. Note that 0x0 refers to evidence not submitted by any party.
    *  @param _evidence A URI to the evidence JSON file whose name should be its keccak256 hash followed by .json.
    */
  event Evidence(Arbitrator indexed _arbitrator, uint indexed _evidenceGroupID, address indexed _party, string _evidence);

  /** @dev To be raised when a ruling is given.
    *  @param _arbitrator The arbitrator giving the ruling.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _ruling The ruling which was given.
    */
  event Ruling(Arbitrator indexed _arbitrator, uint indexed _disputeID, uint _ruling);

  /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
    *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function rule(uint _disputeID, uint _ruling) external;
}

/** @title Arbitrable
*  Arbitrable abstract contract.
*  When developing arbitrable contracts, we need to:
*  -Define the action taken when a ruling is received by the contract. We should do so in executeRuling.
*  -Allow dispute creation. For this a function must:
*      -Call arbitrator.createDispute.value(_fee)(_choices,_extraData);
*      -Create the event Dispute(_arbitrator,_disputeID,_rulingOptions);
*/
contract Arbitrable is IArbitrable {
  Arbitrator public arbitrator;
  bytes public arbitratorExtraData; // Extra data to require particular dispute and appeal behaviour.

  /** @dev Constructor. Choose the arbitrator.
    *  @param _arbitrator The arbitrator of the contract.
    *  @param _arbitratorExtraData Extra data for the arbitrator.
    */
  constructor(Arbitrator _arbitrator, bytes memory _arbitratorExtraData) public {
    arbitrator = _arbitrator;
    arbitratorExtraData = _arbitratorExtraData;
  }

  /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
    *  The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function rule(uint _disputeID, uint _ruling) public {
    emit Ruling(Arbitrator(msg.sender), _disputeID, _ruling);

    executeRuling(_disputeID,_ruling);
  }


  /** @dev Execute a ruling of a dispute.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function executeRuling(uint _disputeID, uint _ruling) internal;
}

/** @title Arbitrator
 *  Arbitrator abstract contract.
 *  When developing arbitrator contracts we need to:
 *  -Define the functions for dispute creation (createDispute) and appeal (appeal). Don't forget to store the arbitrated contract and the disputeID (which should be unique, use nbDisputes).
 *  -Define the functions for cost display (arbitrationCost and appealCost).
 *  -Allow giving rulings. For this a function must call arbitrable.rule(disputeID, ruling).
 */
contract Arbitrator {
  enum DisputeStatus {Waiting, Appealable, Solved}

  modifier requireArbitrationFee(bytes memory _extraData) {
      require(msg.value >= arbitrationCost(_extraData), "Not enough ETH to cover arbitration costs.");
      _;
  }
  modifier requireAppealFee(uint _disputeID, bytes memory _extraData) {
      require(msg.value >= appealCost(_disputeID, _extraData), "Not enough ETH to cover appeal costs.");
      _;
  }

  /** @dev To be raised when a dispute is created.
    *  @param _disputeID ID of the dispute.
    *  @param _arbitrable The contract which created the dispute.
    */
  event DisputeCreation(uint indexed _disputeID, Arbitrable indexed _arbitrable);

  /** @dev To be raised when a dispute can be appealed.
    *  @param _disputeID ID of the dispute.
    */
  event AppealPossible(uint indexed _disputeID, Arbitrable indexed _arbitrable);

  /** @dev To be raised when the current ruling is appealed.
    *  @param _disputeID ID of the dispute.
    *  @param _arbitrable The contract which created the dispute.
    */
  event AppealDecision(uint indexed _disputeID, Arbitrable indexed _arbitrable);

  /** @dev Create a dispute. Must be called by the arbitrable contract.
    *  Must be paid at least arbitrationCost(_extraData).
    *  @param _choices Amount of choices the arbitrator can make in this dispute.
    *  @param _extraData Can be used to give additional info on the dispute to be created.
    *  @return disputeID ID of the dispute created.
    */
  function createDispute(uint _choices, bytes memory _extraData) public requireArbitrationFee(_extraData) payable returns(uint disputeID) {}

  /** @dev Compute the cost of arbitration. It is recommended not to increase it often, as it can be highly time and gas consuming for the arbitrated contracts to cope with fee augmentation.
    *  @param _extraData Can be used to give additional info on the dispute to be created.
    *  @return fee Amount to be paid.
    */
  function arbitrationCost(bytes memory _extraData) public view returns(uint fee);

  /** @dev Appeal a ruling. Note that it has to be called before the arbitrator contract calls rule.
    *  @param _disputeID ID of the dispute to be appealed.
    *  @param _extraData Can be used to give extra info on the appeal.
    */
  function appeal(uint _disputeID, bytes memory _extraData) public requireAppealFee(_disputeID,_extraData) payable {
      emit AppealDecision(_disputeID, Arbitrable(msg.sender));
  }

  /** @dev Compute the cost of appeal. It is recommended not to increase it often, as it can be higly time and gas consuming for the arbitrated contracts to cope with fee augmentation.
    *  @param _disputeID ID of the dispute to be appealed.
    *  @param _extraData Can be used to give additional info on the dispute to be created.
    *  @return fee Amount to be paid.
    */
  function appealCost(uint _disputeID, bytes memory _extraData) public view returns(uint fee);

  /** @dev Compute the start and end of the dispute's current or next appeal period, if possible.
    *  @param _disputeID ID of the dispute.
    *  @return The start and end of the period.
    */
  function appealPeriod(uint _disputeID) public view returns(uint start, uint end) {}

  /** @dev Return the status of a dispute.
    *  @param _disputeID ID of the dispute to rule.
    *  @return status The status of the dispute.
    */
  function disputeStatus(uint _disputeID) public view returns(DisputeStatus status);

  /** @dev Return the current ruling of a dispute. This is useful for parties to know if they should appeal.
    *  @param _disputeID ID of the dispute.
    *  @return ruling The ruling which has been given or the one which will be given if there is no appeal.
    */
  function currentRuling(uint _disputeID) public view returns(uint ruling);
}

/** @title Centralized Arbitrator
 *  @dev This is a centralized arbitrator deciding alone on the result of disputes. No appeals are possible.
 */
contract CentralizedArbitrator is Arbitrator {

  address public owner = msg.sender;
  uint arbitrationPrice; // Not public because arbitrationCost already acts as an accessor.
  uint constant NOT_PAYABLE_VALUE = (2**256-2)/2; // High value to be sure that the appeal is too expensive.

  struct DisputeStruct {
    Arbitrable arbitrated;
    uint choices;
    uint fee;
    uint ruling;
    DisputeStatus status;
  }

  modifier onlyOwner {require(msg.sender==owner, "Can only be called by the owner."); _;}

  DisputeStruct[] public disputes;

  /** @dev Constructor. Set the initial arbitration price.
    *  @param _arbitrationPrice Amount to be paid for arbitration.
    */
  constructor(uint _arbitrationPrice) public {
    arbitrationPrice = _arbitrationPrice;
  }

  /** @dev Set the arbitration price. Only callable by the owner.
    *  @param _arbitrationPrice Amount to be paid for arbitration.
    */
  function setArbitrationPrice(uint _arbitrationPrice) public onlyOwner {
    arbitrationPrice = _arbitrationPrice;
  }

  /** @dev Cost of arbitration. Accessor to arbitrationPrice.
    *  @param _extraData Not used by this contract.
    *  @return fee Amount to be paid.
    */
  function arbitrationCost(bytes memory _extraData) public view returns(uint fee) {
    return arbitrationPrice;
  }

  /** @dev Cost of appeal. Since it is not possible, it's a high value which can never be paid.
    *  @param _disputeID ID of the dispute to be appealed. Not used by this contract.
    *  @param _extraData Not used by this contract.
    *  @return fee Amount to be paid.
    */
  function appealCost(uint _disputeID, bytes memory _extraData) public view returns(uint fee) {
    return NOT_PAYABLE_VALUE;
  }

  /** @dev Create a dispute. Must be called by the arbitrable contract.
    *  Must be paid at least arbitrationCost().
    *  @param _choices Amount of choices the arbitrator can make in this dispute. When ruling ruling<=choices.
    *  @param _extraData Can be used to give additional info on the dispute to be created.
    *  @return disputeID ID of the dispute created.
    */
  function createDispute(uint _choices, bytes memory _extraData) public payable returns(uint disputeID)  {
    super.createDispute(_choices, _extraData);
    disputeID = disputes.push(DisputeStruct({
      arbitrated: Arbitrable(msg.sender),
      choices: _choices,
      fee: msg.value,
      ruling: 0,
      status: DisputeStatus.Waiting
      })) - 1; // Create the dispute and return its number.
    emit DisputeCreation(disputeID, Arbitrable(msg.sender));
  }

  /** @dev Give a ruling. UNTRUSTED.
    *  @param _disputeID ID of the dispute to rule.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
    */
  function _giveRuling(uint _disputeID, uint _ruling) internal {
    DisputeStruct storage dispute = disputes[_disputeID];
    require(_ruling <= dispute.choices, "Invalid ruling.");
    require(dispute.status != DisputeStatus.Solved, "The dispute must not be solved already.");

    dispute.ruling = _ruling;
    dispute.status = DisputeStatus.Solved;

    msg.sender.send(dispute.fee); // Avoid blocking.
    dispute.arbitrated.rule(_disputeID,_ruling);
  }

  /** @dev Give a ruling. UNTRUSTED.
    *  @param _disputeID ID of the dispute to rule.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 means "Not able/wanting to make a decision".
    */
  function giveRuling(uint _disputeID, uint _ruling) public onlyOwner {
    return _giveRuling(_disputeID, _ruling);
  }

  /** @dev Return the status of a dispute.
    *  @param _disputeID ID of the dispute to rule.
    *  @return status The status of the dispute.
    */
  function disputeStatus(uint _disputeID) public view returns(DisputeStatus status) {
    return disputes[_disputeID].status;
  }

  /** @dev Return the ruling of a dispute.
    *  @param _disputeID ID of the dispute to rule.
    *  @return ruling The ruling which would or has been given.
    */
  function currentRuling(uint _disputeID) public view returns(uint ruling) {
    return disputes[_disputeID].ruling;
  }
}

/**
 *  @title AppealableArbitrator
 *  @dev A centralized arbitrator that can be appealed.
 */
contract AppealableArbitrator is CentralizedArbitrator, Arbitrable {
  /* Structs */

  struct AppealDispute {
    uint rulingTime;
    Arbitrator arbitrator;
    uint appealDisputeID;
  }

  /* Storage */

  uint public timeOut;
  mapping(uint => AppealDispute) public appealDisputes;
  mapping(uint => uint) public appealDisputeIDsToDisputeIDs;

  /* Constructor */

  /** @dev Constructs the `AppealableArbitrator` contract.
    *  @param _arbitrationPrice The amount to be paid for arbitration.
    *  @param _arbitrator The back up arbitrator.
    *  @param _arbitratorExtraData Not used by this contract.
    *  @param _timeOut The time out for the appeal period.
    */
  constructor(
      uint _arbitrationPrice,
      Arbitrator _arbitrator,
      bytes memory _arbitratorExtraData,
      uint _timeOut
  ) public CentralizedArbitrator(_arbitrationPrice) Arbitrable(_arbitrator, _arbitratorExtraData) {
    timeOut = _timeOut;
  }

  /* External */

  /** @dev Changes the back up arbitrator.
    *  @param _arbitrator The new back up arbitrator.
    */
  function changeArbitrator(Arbitrator _arbitrator) external onlyOwner {
    arbitrator = _arbitrator;
  }

  /** @dev Changes the time out.
    *  @param _timeOut The new time out.
    */
  function changeTimeOut(uint _timeOut) external onlyOwner {
    timeOut = _timeOut;
  }

  /* External Views */

  /** @dev Gets the specified dispute's latest appeal ID.
    *  @param _disputeID The ID of the dispute.
    */
  function getAppealDisputeID(uint _disputeID) external view returns(uint disputeID) {
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0)))
      disputeID = AppealableArbitrator(address(appealDisputes[_disputeID].arbitrator)).getAppealDisputeID(appealDisputes[_disputeID].appealDisputeID);
    else disputeID = _disputeID;
  }

  /* Public */

  /** @dev Appeals a ruling.
    *  @param _disputeID The ID of the dispute.
    *  @param _extraData Additional info about the appeal.
    */
  function appeal(uint _disputeID, bytes memory _extraData) public payable requireAppealFee(_disputeID, _extraData) {
    super.appeal(_disputeID, _extraData);
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0)))
      appealDisputes[_disputeID].arbitrator.appeal.value(msg.value)(appealDisputes[_disputeID].appealDisputeID, _extraData);
    else {
      appealDisputes[_disputeID].arbitrator = arbitrator;
      appealDisputes[_disputeID].appealDisputeID = arbitrator.createDispute.value(msg.value)(disputes[_disputeID].choices, _extraData);
      appealDisputeIDsToDisputeIDs[appealDisputes[_disputeID].appealDisputeID] = _disputeID;
    }
  }

  /** @dev Gives a ruling.
    *  @param _disputeID The ID of the dispute.
    *  @param _ruling The ruling.
    */
  function giveRuling(uint _disputeID, uint _ruling) public {
    require(disputes[_disputeID].status != DisputeStatus.Solved, "The specified dispute is already resolved.");
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0))) {
      require(Arbitrator(msg.sender) == appealDisputes[_disputeID].arbitrator, "Appealed disputes must be ruled by their back up arbitrator.");
      super._giveRuling(_disputeID, _ruling);
    } else {
      require(msg.sender == owner, "Not appealed disputes must be ruled by the owner.");
      if (disputes[_disputeID].status == DisputeStatus.Appealable) {
        if (now - appealDisputes[_disputeID].rulingTime > timeOut)
          super._giveRuling(_disputeID, disputes[_disputeID].ruling);
        else revert("Time out time has not passed yet.");
      } else {
        disputes[_disputeID].ruling = _ruling;
        disputes[_disputeID].status = DisputeStatus.Appealable;
        appealDisputes[_disputeID].rulingTime = now;
        emit AppealPossible(_disputeID, disputes[_disputeID].arbitrated);
      }
    }
  }

  /* Public Views */

  /** @dev Gets the cost of appeal for the specified dispute.
    *  @param _disputeID The ID of the dispute.
    *  @param _extraData Additional info about the appeal.
    *  @return The cost of the appeal.
    */
  function appealCost(uint _disputeID, bytes memory _extraData) public view returns(uint cost) {
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0)))
      cost = appealDisputes[_disputeID].arbitrator.appealCost(appealDisputes[_disputeID].appealDisputeID, _extraData);
    else if (disputes[_disputeID].status == DisputeStatus.Appealable) cost = arbitrator.arbitrationCost(_extraData);
    else cost = NOT_PAYABLE_VALUE;
  }

  /** @dev Gets the status of the specified dispute.
    *  @param _disputeID The ID of the dispute.
    *  @return The status.
    */
  function disputeStatus(uint _disputeID) public view returns(DisputeStatus status) {
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0)))
      status = appealDisputes[_disputeID].arbitrator.disputeStatus(appealDisputes[_disputeID].appealDisputeID);
    else status = disputes[_disputeID].status;
  }

  /** @dev Return the ruling of a dispute.
    *  @param _disputeID ID of the dispute to rule.
    *  @return ruling The ruling which would or has been given.
    */
  function currentRuling(uint _disputeID) public view returns(uint ruling) {
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0))) // Appealed.
      ruling = appealDisputes[_disputeID].arbitrator.currentRuling(appealDisputes[_disputeID].appealDisputeID); // Retrieve ruling from the arbitrator whom the dispute is appealed to.
    else ruling = disputes[_disputeID].ruling; //  Not appealed, basic case.
  }

  /* Internal */

  /** @dev Executes the ruling of the specified dispute.
    *  @param _disputeID The ID of the dispute.
    *  @param _ruling The ruling.
    */
  function executeRuling(uint _disputeID, uint _ruling) internal {
    require(
      appealDisputes[appealDisputeIDsToDisputeIDs[_disputeID]].arbitrator != Arbitrator(address(0)),
      "The dispute must have been appealed."
    );
    giveRuling(appealDisputeIDsToDisputeIDs[_disputeID], _ruling);
  }
}

/**
 *  @title EnhancedAppealableArbitrator
 *  @author Enrique Piqueras - <epiquerass@gmail.com>
 *  @dev Implementation of `AppealableArbitrator` that supports `appealPeriod`.
 */
contract EnhancedAppealableArbitrator is AppealableArbitrator {
  /* Constructor */

  /** @dev Constructs the `EnhancedAppealableArbitrator` contract.
    *  @param _arbitrationPrice The amount to be paid for arbitration.
    *  @param _arbitrator The back up arbitrator.
    *  @param _arbitratorExtraData Not used by this contract.
    *  @param _timeOut The time out for the appeal period.
    */
  constructor(
    uint _arbitrationPrice,
    Arbitrator _arbitrator,
    bytes memory _arbitratorExtraData,
    uint _timeOut
  ) public AppealableArbitrator(_arbitrationPrice, _arbitrator, _arbitratorExtraData, _timeOut) {}

  /* Public Views */

  /** @dev Compute the start and end of the dispute's current or next appeal period, if possible.
    *  @param _disputeID ID of the dispute.
    *  @return The start and end of the period.
    */
  function appealPeriod(uint _disputeID) public view returns(uint start, uint end) {
    if (appealDisputes[_disputeID].arbitrator != Arbitrator(address(0)))
      (start, end) = appealDisputes[_disputeID].arbitrator.appealPeriod(appealDisputes[_disputeID].appealDisputeID);
    else {
      start = appealDisputes[_disputeID].rulingTime;
      require(start != 0, "The specified dispute is not appealable.");
      end = start + timeOut;
    }
  }
}

/**
 *  @title Permission Interface
 *  This is a permission interface for arbitrary values. The values can be cast to the required types.
 */
interface PermissionInterface {
  /**
    *  @dev Return true if the value is allowed.
    *  @param _value The value we want to check.
    *  @return allowed True if the value is allowed, false otherwise.
    */
  function isPermitted(bytes32 _value) external view returns (bool allowed);
}

/**
 *  @title ArbitrableBetList
 *  This smart contract is a viewer moderation for the bet goal contract.
 */
contract ArbitrableBetList is IArbitrable {
  using CappedMath for uint; // Operations bounded between 0 and 2**256 - 1.

  /* Enums */

  enum BetStatus {
    Absent, // The bet is not in the registry.
    Registered, // The bet is in the registry.
    RegistrationRequested, // The bet has a request to be added to the registry.
    ClearingRequested // The bet has a request to be removed from the registry.
  }

  enum Party {
    None,      // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
    Requester, // Party that made the request to change a bet status.
    Challenger // Party that challenges the request to change a bet status.
  }

  // ************************ //
  // *  Request Life Cycle  * //
  // ************************ //
  // Changes to the bet status are made via requests for either listing or removing a bet from the Bet Curated Registry.
  // To make or challenge a request, a party must pay a deposit. This value will be rewarded to the party that ultimately wins a dispute. If no one challenges the request, the value will be reimbursed to the requester.
  // Additionally to the challenge reward, in the case a party challenges a request, both sides must fully pay the amount of arbitration fees required to raise a dispute. The party that ultimately wins the case will be reimbursed.
  // Finally, arbitration fees can be crowdsourced. To incentivise insurers, an additional fee stake must be deposited. Contributors that fund the side that ultimately wins a dispute will be reimbursed and rewarded with the other side's fee stake proportionally to their contribution.
  // In summary, costs for placing or challenging a request are the following:
  // - A challenge reward given to the party that wins a potential dispute.
  // - Arbitration fees used to pay jurors.
  // - A fee stake that is distributed among insurers of the side that ultimately wins a dispute.

  /* Structs */

  struct Bet {
    BetStatus status; // The status of the bet.
    Request[] requests; // List of status change requests made for the bet.
  }

  // Some arrays below have 3 elements to map with the Party enums for better readability:
  // - 0: is unused, matches `Party.None`.
  // - 1: for `Party.Requester`.
  // - 2: for `Party.Challenger`.
  struct Request {
    bool disputed; // True if a dispute was raised.
    uint disputeID; // ID of the dispute, if any.
    uint submissionTime; // Time when the request was made. Used to track when the challenge period ends.
    bool resolved; // True if the request was executed and/or any disputes raised were resolved.
    address[3] parties; // Address of requester and challenger, if any.
    Round[] rounds; // Tracks each round of a dispute.
    Party ruling; // The final ruling given, if any.
    Arbitrator arbitrator; // The arbitrator trusted to solve disputes for this request.
    bytes arbitratorExtraData; // The extra data for the trusted arbitrator of this request.
  }

  struct Round {
    uint[3] paidFees; // Tracks the fees paid by each side on this round.
    bool[3] hasPaid; // True when the side has fully paid its fee. False otherwise.
    uint feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
    mapping(address => uint[3]) contributions; // Maps contributors to their contributions for each side.
  }

  /* Storage */

  // Constants

  uint RULING_OPTIONS = 2; // The amount of non 0 choices the arbitrator can give.

  // Settings
  address public governor; // The address that can make governance changes to the parameters of the Bet Curated Registry.
  Arbitrator arbitrator;
  bytes public arbitratorExtraData;
  address public goalBetRegistry; // The address of the goalBetRegistry contract.
  uint public requesterBaseDeposit; // The base deposit to make a request.
  uint public challengerBaseDeposit; // The base deposit to challenge a request.
  uint public challengePeriodDuration; // The time before a request becomes executable if not challenged.
  uint public metaEvidenceUpdates; // The number of times the meta evidence has been updated. Used to track the latest meta evidence ID.

  // The required fee stake that a party must pay depends on who won the previous round and is proportional to the arbitration cost such that the fee stake for a round is stake multiplier * arbitration cost for that round.
  // Multipliers are in basis points.
  uint public winnerStakeMultiplier; // Multiplier for calculating the fee stake paid by the party that won the previous round.
  uint public loserStakeMultiplier; // Multiplier for calculating the fee stake paid by the party that lost the previous round.
  uint public sharedStakeMultiplier; // Multiplier for calculating the fee stake that must be paid in the case where there isn't a winner and loser (e.g. when it's the first round or the arbitrator ruled "refused to rule"/"could not rule").
  uint public constant MULTIPLIER_DIVISOR = 10000; // Divisor parameter for multipliers.

  // Registry data.
  mapping(uint => Bet) public bets; // Maps the uint bet to the bet data.
  mapping(address => mapping(uint => uint)) public arbitratorDisputeIDToBetID; // Maps a dispute ID to the bet with the disputed request.
  uint[] public betList; // List of submitted bets.

  /* Modifiers */

  modifier onlyGovernor {require(msg.sender == governor, "The caller must be the governor."); _;}

  /* Events */

  /**
    *  @dev Emitted when a party submits a new bet.
    *  @param _betID The bet.
    *  @param _requester The address of the party that made the request.
    */
  event BetSubmitted(uint indexed _betID, address indexed _requester);

  /** @dev Emitted when a party makes a request to change a bet status.
    * @param _betID The bet index.
    * @param _registrationRequest Whether the request is a registration request. False means it is a clearing request.
    */
  event RequestSubmitted(uint indexed _betID, bool _registrationRequest);

  /**
    *  @dev Emitted when a party makes a request, dispute or appeals are raised, or when a request is resolved.
    *  @param _requester Address of the party that submitted the request.
    *  @param _challenger Address of the party that has challenged the request, if any.
    *  @param _betID The address.
    *  @param _status The status of the bet.
    *  @param _disputed Whether the bet is disputed.
    *  @param _appealed Whether the current round was appealed.
    */
  event BetStatusChange(
    address indexed _requester,
    address indexed _challenger,
    uint indexed _betID,
    BetStatus _status,
    bool _disputed,
    bool _appealed
  );

  /** @dev Emitted when a reimbursements and/or contribution rewards are withdrawn.
    *  @param _betID The bet ID from which the withdrawal was made.
    *  @param _contributor The address that sent the contribution.
    *  @param _request The request from which the withdrawal was made.
    *  @param _round The round from which the reward was taken.
    *  @param _value The value of the reward.
    */
  event RewardWithdrawal(uint indexed _betID, address indexed _contributor, uint indexed _request, uint _round, uint _value);


  /* Constructor */

  /**
    *  @dev Constructs the arbitrable token curated registry.
    *  @param _arbitrator The trusted arbitrator to resolve potential disputes.
    *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
    *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
    *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
    *  @param _governor The trusted governor of this contract.
    *  @param _requesterBaseDeposit The base deposit to make a request.
    *  @param _challengerBaseDeposit The base deposit to challenge a request.
    *  @param _challengePeriodDuration The time in seconds, parties have to challenge a request.
    *  @param _sharedStakeMultiplier Multiplier of the arbitration cost that each party must pay as fee stake for a round when there isn't a winner/loser in the previous round (e.g. when it's the first round or the arbitrator refused to or did not rule). In basis points.
    *  @param _winnerStakeMultiplier Multiplier of the arbitration cost that the winner has to pay as fee stake for a round in basis points.
    *  @param _loserStakeMultiplier Multiplier of the arbitration cost that the loser has to pay as fee stake for a round in basis points.
    */
  constructor(
    Arbitrator _arbitrator,
    bytes memory _arbitratorExtraData,
    string memory _registrationMetaEvidence,
    string memory _clearingMetaEvidence,
    address _governor,
    uint _requesterBaseDeposit,
    uint _challengerBaseDeposit,
    uint _challengePeriodDuration,
    uint _sharedStakeMultiplier,
    uint _winnerStakeMultiplier,
    uint _loserStakeMultiplier
  ) public {
    emit MetaEvidence(0, _registrationMetaEvidence);
    emit MetaEvidence(1, _clearingMetaEvidence);

    governor = _governor;
    arbitrator = _arbitrator;
    arbitratorExtraData = _arbitratorExtraData;
    requesterBaseDeposit = _requesterBaseDeposit;
    challengerBaseDeposit = _challengerBaseDeposit;
    challengePeriodDuration = _challengePeriodDuration;
    sharedStakeMultiplier = _sharedStakeMultiplier;
    winnerStakeMultiplier = _winnerStakeMultiplier;
    loserStakeMultiplier = _loserStakeMultiplier;
  }


  /* External and Public */

  // ************************ //
  // *       Requests       * //
  // ************************ //

  /** @dev Submits a request to change an address status. Accepts enough ETH to fund a potential dispute considering the current required amount and reimburses the rest. TRUSTED.
    * @param _betID The address.
    */
  function requestStatusChange(uint _betID)
      external
      payable
  {
    Bet storage bet = bets[_betID];

    if (bet.requests.length == 0) {
      require(msg.sender == goalBetRegistry); // Only the bet Registry can send a new bet.
      // Initial bet registration.
      betList.push(_betID);
      emit BetSubmitted(_betID, msg.sender);
    }

    // Update bet status.
    if (bet.status == BetStatus.Absent)
      bet.status = BetStatus.RegistrationRequested;
    else if (bet.status == BetStatus.Registered)
      bet.status = BetStatus.ClearingRequested;
    else
      revert("Bet already has a pending request.");

    // Setup request.
    Request storage request = bet.requests[bet.requests.length++];
    request.parties[uint(Party.Requester)] = msg.sender;
    request.submissionTime = now;
    request.arbitrator = arbitrator;
    request.arbitratorExtraData = arbitratorExtraData;
    Round storage round = request.rounds[request.rounds.length++];

    emit RequestSubmitted(_betID, bet.status == BetStatus.RegistrationRequested);

    // Amount required to fully the requester: requesterBaseDeposit + arbitration cost + (arbitration cost * multiplier).
    uint arbitrationCost = request.arbitrator.arbitrationCost(request.arbitratorExtraData);
    uint totalCost = arbitrationCost.addCap((arbitrationCost.mulCap(sharedStakeMultiplier)) / MULTIPLIER_DIVISOR).addCap(requesterBaseDeposit);
    contribute(round, Party.Requester, msg.sender, msg.value, totalCost);
    require(round.paidFees[uint(Party.Requester)] >= totalCost, "You must fully fund your side.");
    round.hasPaid[uint(Party.Requester)] = true;

    emit BetStatusChange(
      request.parties[uint(Party.Requester)],
      address(0x0),
      _betID,
      bet.status,
      false,
      false
    );
  }

  /** @dev Challenges the latest request of a bet. Accepts enough ETH to fund a potential dispute considering the current required amount. Reimburses unused ETH. TRUSTED.
    *  @param _betID The bet ID with the request to challenge.
    *  @param _evidence A link to an evidence using its URI. Ignored if not provided or if not enough funds were provided to create a dispute.
    */
  function challengeRequest(uint _betID, string calldata  _evidence) external payable {
    Bet storage bet = bets[_betID];
    require(
      bet.status == BetStatus.RegistrationRequested || bet.status == BetStatus.ClearingRequested,
      "The bet must have a pending request."
    );
    Request storage request = bet.requests[bet.requests.length - 1];
    require(now - request.submissionTime <= challengePeriodDuration, "Challenges must occur during the challenge period.");
    require(!request.disputed, "The request should not have already been disputed.");

    // Take the deposit and save the challenger's bet.
    request.parties[uint(Party.Challenger)] = msg.sender;

    Round storage round = request.rounds[request.rounds.length - 1];
    uint arbitrationCost = request.arbitrator.arbitrationCost(request.arbitratorExtraData);
    uint totalCost = arbitrationCost.addCap((arbitrationCost.mulCap(sharedStakeMultiplier)) / MULTIPLIER_DIVISOR).addCap(challengerBaseDeposit);
    contribute(round, Party.Challenger, msg.sender, msg.value, totalCost);
    require(round.paidFees[uint(Party.Challenger)] >= totalCost, "You must fully fund your side.");
    round.hasPaid[uint(Party.Challenger)] = true;

    // Raise a dispute.
    request.disputeID = request.arbitrator.createDispute.value(arbitrationCost)(RULING_OPTIONS, request.arbitratorExtraData);
    arbitratorDisputeIDToBetID[address(request.arbitrator)][request.disputeID] = _betID;
    request.disputed = true;
    request.rounds.length++;
    round.feeRewards = round.feeRewards.subCap(arbitrationCost);

    emit Dispute(
      request.arbitrator,
      request.disputeID,
      bet.status == BetStatus.RegistrationRequested
        ? 2 * metaEvidenceUpdates
        : 2 * metaEvidenceUpdates + 1,
      uint(keccak256(abi.encodePacked(_betID,bet.requests.length - 1)))
    );

    emit BetStatusChange(
      request.parties[uint(Party.Requester)],
      request.parties[uint(Party.Challenger)],
      _betID,
      bet.status,
      true,
      false
    );

    if (bytes(_evidence).length > 0)
      emit Evidence(request.arbitrator, uint(keccak256(abi.encodePacked(_betID,bet.requests.length - 1))), msg.sender, _evidence);
  }

  /** @dev Takes up to the total amount required to fund a side of an appeal. Reimburses the rest. Creates an appeal if both sides are fully funded. TRUSTED.
    * @param _betID The bet index.
    * @param _side The recipient of the contribution.
    */
  function fundAppeal(uint _betID, Party _side) external payable {
    // Recipient must be either the requester or challenger.
    require(_side == Party.Requester || _side == Party.Challenger); // solium-disable-line error-reason
    Bet storage bet = bets[_betID];
    require(
      bet.status == BetStatus.RegistrationRequested || bet.status == BetStatus.ClearingRequested,
      "The bet must have a pending request."
    );
    Request storage request = bet.requests[bet.requests.length - 1];
    require(request.disputed, "A dispute must have been raised to fund an appeal.");
    (uint appealPeriodStart, uint appealPeriodEnd) = request.arbitrator.appealPeriod(request.disputeID);
    require(
      now >= appealPeriodStart && now < appealPeriodEnd,
      "Contributions must be made within the appeal period."
    );

    // Amount required to fully fund each side: arbitration cost + (arbitration cost * multiplier)
    Round storage round = request.rounds[request.rounds.length - 1];
    Party winner = Party(request.arbitrator.currentRuling(request.disputeID));
    Party loser;
    if (winner == Party.Requester)
      loser = Party.Challenger;
    else if (winner == Party.Challenger)
      loser = Party.Requester;
    require(!(_side==loser) || (now-appealPeriodStart < (appealPeriodEnd-appealPeriodStart)/2), "The loser must contribute during the first half of the appeal period.");

    uint multiplier;
    if (_side == winner)
      multiplier = winnerStakeMultiplier;
    else if (_side == loser)
      multiplier = loserStakeMultiplier;
    else
      multiplier = sharedStakeMultiplier;
    uint appealCost = request.arbitrator.appealCost(request.disputeID, request.arbitratorExtraData);
    uint totalCost = appealCost.addCap((appealCost.mulCap(multiplier)) / MULTIPLIER_DIVISOR);
    contribute(round, _side, msg.sender, msg.value, totalCost);
    if (round.paidFees[uint(_side)] >= totalCost)
      round.hasPaid[uint(_side)] = true;

    // Raise appeal if both sides are fully funded.
    if (round.hasPaid[uint(Party.Challenger)] && round.hasPaid[uint(Party.Requester)]) {
      request.arbitrator.appeal.value(appealCost)(request.disputeID, request.arbitratorExtraData);
      request.rounds.length++;
      round.feeRewards = round.feeRewards.subCap(appealCost);
      emit BetStatusChange(
        request.parties[uint(Party.Requester)],
        request.parties[uint(Party.Challenger)],
        _betID,
        bet.status,
        true,
        true
      );
    }
  }

  /** @dev Reimburses contributions if no disputes were raised. If a dispute was raised, sends the fee stake rewards and reimbursements proportional to the contributions made to the winner of a dispute.
    *  @param _beneficiary The address that made contributions to a request.
    *  @param _betID The bet index submission with the request from which to withdraw.
    *  @param _request The request from which to withdraw.
    *  @param _round The round from which to withdraw.
    */
  function withdrawFeesAndRewards(address payable _beneficiary, uint _betID, uint _request, uint _round) public {
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[_request];
    Round storage round = request.rounds[_round];
    // The request must be executed and there can be no disputes pending resolution.
    require(request.resolved); // solium-disable-line error-reason

    uint reward;
    if (!request.disputed || request.ruling == Party.None) {
      // No disputes were raised, or there isn't a winner and loser. Reimburse unspent fees proportionally.
      uint rewardRequester = round.paidFees[uint(Party.Requester)] > 0
        ? (round.contributions[_beneficiary][uint(Party.Requester)] * round.feeRewards) / (round.paidFees[uint(Party.Challenger)] + round.paidFees[uint(Party.Requester)])
        : 0;
      uint rewardChallenger = round.paidFees[uint(Party.Challenger)] > 0
        ? (round.contributions[_beneficiary][uint(Party.Challenger)] * round.feeRewards) / (round.paidFees[uint(Party.Challenger)] + round.paidFees[uint(Party.Requester)])
        : 0;

      reward = rewardRequester + rewardChallenger;
      round.contributions[_beneficiary][uint(Party.Requester)] = 0;
      round.contributions[_beneficiary][uint(Party.Challenger)] = 0;
    } else {
      // Reward the winner.
      reward = round.paidFees[uint(request.ruling)] > 0
        ? (round.contributions[_beneficiary][uint(request.ruling)] * round.feeRewards) / round.paidFees[uint(request.ruling)]
        : 0;

      round.contributions[_beneficiary][uint(request.ruling)] = 0;
    }

    emit RewardWithdrawal(_betID, _beneficiary, _request, _round,  reward);

    _beneficiary.send(reward); // It is the user responsibility to accept ETH.
  }

  /** @dev Withdraws rewards and reimbursements of multiple rounds at once. This function is O(n) where n is the number of rounds. This could exceed gas limits, therefore this function should be used only as a utility and not be relied upon by other contracts.
    *  @param _beneficiary The address that made contributions to the request.
    *  @param _betID The bet index.
    *  @param _request The request from which to withdraw contributions.
    *  @param _cursor The round from where to start withdrawing.
    *  @param _count Rounds greater or equal to this value won't be withdrawn. If set to 0 or a value larger than the number of rounds, iterates until the last round.
    */
  function batchRoundWithdraw(address payable _beneficiary, uint _betID, uint _request, uint _cursor, uint _count) public {
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[_request];
    for (uint i = _cursor; i<request.rounds.length && (_count==0 || i<_count); i++)
      withdrawFeesAndRewards(_beneficiary, _betID, _request, i);
  }

  /** @dev Withdraws rewards and reimbursements of multiple requests at once. This function is O(n*m) where n is the number of requests and m is the number of rounds. This could exceed gas limits, therefore this function should be used only as a utility and not be relied upon by other contracts.
    *  @param _beneficiary The address that made contributions to the request.
    *  @param _betID The bet index.
    *  @param _cursor The request from which to start withdrawing.
    *  @param _count Requests greater or equal to this value won't be withdrawn. If set to 0 or a value larger than the number of request, iterates until the last request.
    *  @param _roundCursor The round of each request from where to start withdrawing.
    *  @param _roundCount Rounds greater or equal to this value won't be withdrawn. If set to 0 or a value larger than the number of rounds a request has, iteration for that request will stop at the last round.
    */
  function batchRequestWithdraw(
      address payable _beneficiary,
      uint _betID,
      uint _cursor,
      uint _count,
      uint _roundCursor,
      uint _roundCount
  ) external {
    Bet storage bet = bets[_betID];
    for (uint i = _cursor; i<bet.requests.length && (_count==0 || i<_count); i++)
      batchRoundWithdraw(_beneficiary, _betID, i, _roundCursor, _roundCount);
  }

  /** @dev Executes a request if the challenge period passed and no one challenged the request.
    *  @param _betID The bet index with the request to execute.
    */
  function executeRequest(uint _betID) external {
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[bet.requests.length - 1];
    require(
      now - request.submissionTime > challengePeriodDuration,
      "Time to challenge the request must have passed."
    );
    require(!request.disputed, "The request should not be disputed.");

    if (bet.status == BetStatus.RegistrationRequested)
      bet.status = BetStatus.Registered;
    else if (bet.status == BetStatus.ClearingRequested)
      bet.status = BetStatus.Absent;
    else
      revert("There must be a request.");

    request.resolved = true;

    address payable party = address(uint160(request.parties[uint(Party.Requester)]));

    withdrawFeesAndRewards(party, _betID, bet.requests.length - 1, 0); // Automatically withdraw for the requester.

    emit BetStatusChange(
      request.parties[uint(Party.Requester)],
      address(0x0),
      _betID,
      bet.status,
      false,
      false
    );
  }

  /** @dev Give a ruling for a dispute. Can only be called by the arbitrator. TRUSTED.
    * Overrides parent function to account for the situation where the winner loses a case due to paying less appeal fees than expected.
    * @param _disputeID ID of the dispute in the arbitrator contract.
    * @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function rule(uint _disputeID, uint _ruling) public {
    Party resultRuling = Party(_ruling);
    uint _betID = arbitratorDisputeIDToBetID[msg.sender][_disputeID];
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[bet.requests.length - 1];
    Round storage round = request.rounds[request.rounds.length - 1];
    require(_ruling <= RULING_OPTIONS); // solium-disable-line error-reason
    require(address(request.arbitrator) == msg.sender); // solium-disable-line error-reason
    require(!request.resolved); // solium-disable-line error-reason

    // The ruling is inverted if the loser paid its fees.
    if (round.hasPaid[uint(Party.Requester)] == true) // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
      resultRuling = Party.Requester;
    else if (round.hasPaid[uint(Party.Challenger)] == true)
      resultRuling = Party.Challenger;

    emit Ruling(Arbitrator(msg.sender), _disputeID, uint(resultRuling));
    executeRuling(_disputeID, uint(resultRuling));
  }

  /** @dev Submit a reference to evidence. EVENT.
    *  @param _betID The bet index.
    *  @param _evidence A link to an evidence using its URI.
    */
  function submitEvidence(uint _betID, string calldata _evidence) external {
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[bet.requests.length - 1];
    require(!request.resolved, "The dispute must not already be resolved.");

    emit Evidence(request.arbitrator, uint(keccak256(abi.encodePacked(_betID,bet.requests.length - 1))), msg.sender, _evidence);
  }

  // ************************ //
  // *      Governance      * //
  // ************************ //

  /** @dev Change the duration of the challenge period.
    *  @param _challengePeriodDuration The new duration of the challenge period.
    */
  function changeTimeToChallenge(uint _challengePeriodDuration) external onlyGovernor {
    challengePeriodDuration = _challengePeriodDuration;
  }

  /** @dev Change the base amount required as a deposit to make a request.
    *  @param _requesterBaseDeposit The new base amount of wei required to make a request.
    */
  function changeRequesterBaseDeposit(uint _requesterBaseDeposit) external onlyGovernor {
    requesterBaseDeposit = _requesterBaseDeposit;
  }

  /** @dev Change the base amount required as a deposit to challenge a request.
    *  @param _challengerBaseDeposit The new base amount of wei required to challenge a request.
    */
  function changeChallengerBaseDeposit(uint _challengerBaseDeposit) external onlyGovernor {
    challengerBaseDeposit = _challengerBaseDeposit;
  }

  /** @dev Change the governor of the token curated registry.
    *  @param _governor The address of the new governor.
    */
  function changeGovernor(address _governor) external onlyGovernor {
    governor = _governor;
  }

  /** @dev Change the address of the goal bet registry contract.
  *  @param _goalBetRegistry The address of the new goal bet registry contract.
  */
  function changeGoalBetRegistry(address _goalBetRegistry) external onlyGovernor {
    goalBetRegistry = _goalBetRegistry;
  }

  /** @dev Change the percentage of arbitration fees that must be paid as fee stake by parties when there isn't a winner or loser.
    *  @param _sharedStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
    */
  function changeSharedStakeMultiplier(uint _sharedStakeMultiplier) external onlyGovernor {
    sharedStakeMultiplier = _sharedStakeMultiplier;
  }

  /** @dev Change the percentage of arbitration fees that must be paid as fee stake by the winner of the previous round.
    *  @param _winnerStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
    */
  function changeWinnerStakeMultiplier(uint _winnerStakeMultiplier) external onlyGovernor {
    winnerStakeMultiplier = _winnerStakeMultiplier;
  }

  /** @dev Change the percentage of arbitration fees that must be paid as fee stake by the party that lost the previous round.
    *  @param _loserStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
    */
  function changeLoserStakeMultiplier(uint _loserStakeMultiplier) external onlyGovernor {
    loserStakeMultiplier = _loserStakeMultiplier;
  }

  /** @dev Change the arbitrator to be used for disputes that may be raised in the next requests. The arbitrator is trusted to support appeal periods and not reenter.
    *  @param _arbitrator The new trusted arbitrator to be used in the next requests.
    *  @param _arbitratorExtraData The extra data used by the new arbitrator.
    */
  function changeArbitrator(Arbitrator _arbitrator, bytes calldata _arbitratorExtraData) external onlyGovernor {
    arbitrator = _arbitrator;
    arbitratorExtraData = _arbitratorExtraData;
  }

  /** @dev Update the meta evidence used for disputes.
    *  @param _registrationMetaEvidence The meta evidence to be used for future registration request disputes.
    *  @param _clearingMetaEvidence The meta evidence to be used for future clearing request disputes.
    */
  function changeMetaEvidence(string calldata _registrationMetaEvidence, string calldata _clearingMetaEvidence) external onlyGovernor {
    metaEvidenceUpdates++;
    emit MetaEvidence(2 * metaEvidenceUpdates, _registrationMetaEvidence);
    emit MetaEvidence(2 * metaEvidenceUpdates + 1, _clearingMetaEvidence);
  }


  /* Internal */

  /** @dev Returns the contribution value and remainder from available ETH and required amount.
    *  @param _available The amount of ETH available for the contribution.
    *  @param _requiredAmount The amount of ETH required for the contribution.
    *  @return taken The amount of ETH taken.
    *  @return remainder The amount of ETH left from the contribution.
    */
  function calculateContribution(uint _available, uint _requiredAmount)
    internal
    pure
    returns(uint taken, uint remainder)
  {
    if (_requiredAmount > _available)
      return (_available, 0); // Take whatever is available, return 0 as leftover ETH.

    remainder = _available - _requiredAmount;
    return (_requiredAmount, remainder);
  }

  /** @dev Make a fee contribution.
    *  @param _round The round to contribute.
    *  @param _side The side for which to contribute.
    *  @param _contributor The contributor.
    *  @param _amount The amount contributed.
    *  @param _totalRequired The total amount required for this side.
    */
  function contribute(Round storage _round, Party _side, address payable _contributor, uint _amount, uint _totalRequired) internal {
    // Take up to the amount necessary to fund the current round at the current costs.
    uint contribution; // Amount contributed.
    uint remainingETH; // Remaining ETH to send back.
    (contribution, remainingETH) = calculateContribution(_amount, _totalRequired.subCap(_round.paidFees[uint(_side)]));
    _round.contributions[_contributor][uint(_side)] += contribution;
    _round.paidFees[uint(_side)] += contribution;
    _round.feeRewards += contribution;

    // Reimburse leftover ETH.
    _contributor.send(remainingETH); // Deliberate use of send in order to not block the contract in case of reverting fallback.
  }

  /** @dev Execute the ruling of a dispute.
    *  @param _disputeID ID of the dispute in the Arbitrator contract.
    *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function executeRuling(uint _disputeID, uint _ruling) internal {
    uint betID = arbitratorDisputeIDToBetID[msg.sender][_disputeID];
    Bet storage bet = bets[betID];
    Request storage request = bet.requests[bet.requests.length - 1];

    Party winner = Party(_ruling);

    // Update bet state
    if (winner == Party.Requester) { // Execute Request
      if (bet.status == BetStatus.RegistrationRequested)
        bet.status = BetStatus.Registered;
      else
        bet.status = BetStatus.Absent;
    } else { // Revert to previous state.
      if (bet.status == BetStatus.RegistrationRequested)
        bet.status = BetStatus.Absent;
      else if (bet.status == BetStatus.ClearingRequested)
        bet.status = BetStatus.Registered;
    }

    request.resolved = true;
    request.ruling = Party(_ruling);
    // Automatically withdraw.
    if (winner == Party.None) {
      address payable requester = address(uint160(request.parties[uint(Party.Requester)]));
      address payable challenger = address(uint160(request.parties[uint(Party.Challenger)]));

      withdrawFeesAndRewards(requester, betID, bet.requests.length-1, 0);
      withdrawFeesAndRewards(challenger, betID, bet.requests.length-1, 0);
    } else {
      address payable winnerAddr = address(uint160(request.parties[uint(winner)]));

      withdrawFeesAndRewards(winnerAddr, betID, bet.requests.length-1, 0);
    }

    emit BetStatusChange(
      request.parties[uint(Party.Requester)],
      request.parties[uint(Party.Challenger)],
      betID,
      bet.status,
      request.disputed,
      false
    );
  }


  /* Views */

  /** @dev Return true if the bet is on the list.
    *  @param _betID The bet index.
    *  @return allowed True if the address is allowed, false otherwise.
    */
  function isPermitted(uint _betID) external view returns (bool allowed) {
    Bet storage bet = bets[_betID];

    return bet.status == BetStatus.Registered || bet.status == BetStatus.ClearingRequested;
  }


  /* Interface Views */

  /** @dev Return the sum of withdrawable wei of a request an account is entitled to. This function is O(n), where n is the number of rounds of the request. This could exceed the gas limit, therefore this function should only be used for interface display and not by other contracts.
    *  @param _betID The bet index to query.
    *  @param _beneficiary The contributor for which to query.
    *  @param _request The request from which to query for.
    *  @return The total amount of wei available to withdraw.
    */
  function amountWithdrawable(uint _betID, address _beneficiary, uint _request) external view returns (uint total){
    Request storage request = bets[_betID].requests[_request];
    if (!request.resolved) return total;

    for (uint i = 0; i < request.rounds.length; i++) {
      Round storage round = request.rounds[i];
      if (!request.disputed || request.ruling == Party.None) {
        uint rewardRequester = round.paidFees[uint(Party.Requester)] > 0
          ? (round.contributions[_beneficiary][uint(Party.Requester)] * round.feeRewards) / (round.paidFees[uint(Party.Requester)] + round.paidFees[uint(Party.Challenger)])
          : 0;
        uint rewardChallenger = round.paidFees[uint(Party.Challenger)] > 0
          ? (round.contributions[_beneficiary][uint(Party.Challenger)] * round.feeRewards) / (round.paidFees[uint(Party.Requester)] + round.paidFees[uint(Party.Challenger)])
          : 0;

        total += rewardRequester + rewardChallenger;
      } else {
        total += round.paidFees[uint(request.ruling)] > 0
          ? (round.contributions[_beneficiary][uint(request.ruling)] * round.feeRewards) / round.paidFees[uint(request.ruling)]
          : 0;
      }
    }

    return total;
  }

  /** @dev Return the numbers of bets that were submitted. Includes bets that never made it to the list or were later removed.
    *  @return count The numbers of bets in the list.
    */
  function betCount() external view returns (uint count) {
    return betList.length;
  }

  // FIXME: I comment these lines because with these features the contract deployment runs an "out of gas".
  // /** @dev Return the numbers of bets with each status. This function is O(n), where n is the number of bets. This could exceed the gas limit, therefore this function should only be used for interface display and not by other contracts.
  //   *  @return The numbers of bets in the list per status.
  //   */
  // function countByStatus()
  //   external
  //   view
  //   returns (
  //   uint absent,
  //   uint registered,
  //   uint registrationRequest,
  //   uint clearingRequest,
  //   uint challengedRegistrationRequest,
  //   uint challengedClearingRequest
  //   )
  // {
  //   for (uint i = 0; i < betList.length; i++) {
  //     Bet storage bet = bets[betList[i]];
  //     Request storage request = bet.requests[bet.requests.length - 1];

  //     if (bet.status == BetStatus.Absent) absent++;
  //     else if (bet.status == BetStatus.Registered) registered++;
  //     else if (bet.status == BetStatus.RegistrationRequested && !request.disputed) registrationRequest++;
  //     else if (bet.status == BetStatus.ClearingRequested && !request.disputed) clearingRequest++;
  //     else if (bet.status == BetStatus.RegistrationRequested && request.disputed) challengedRegistrationRequest++;
  //     else if (bet.status == BetStatus.ClearingRequested && request.disputed) challengedClearingRequest++;
  //   }
  // }

  // /** @dev Return the values of the bets the query finds. This function is O(n), where n is the number of bets. This could exceed the gas limit, therefore this function should only be used for interface display and not by other contracts.
  //   *  @param _cursor The bet index from which to start iterating. To start from either the oldest or newest item.
  //   *  @param _count The number of bets to return.
  //   *  @param _filter The filter to use. Each element of the array in sequence means:
  //   *  - Include absent bets in result.
  //   *  - Include registered bets in result.
  //   *  - Include bets with registration requests that are not disputed in result.
  //   *  - Include bets with clearing requests that are not disputed in result.
  //   *  - Include disputed bets with registration requests in result.
  //   *  - Include disputed bets with clearing requests in result.
  //   *  - Include bets submitted by the caller.
  //   *  - Include bets challenged by the caller.
  //   *  @param _oldestFirst Whether to sort from oldest to the newest item.
  //   *  @return The values of the bets found and whether there are more bets for the current filter and sort.
  //   */
  // function queryBets(uint _cursor, uint _count, bool[8] calldata _filter, bool _oldestFirst)
  //   external
  //   view
  //   returns (uint[] memory values, bool hasMore)
  // {
  //   uint cursorIndex;
  //   values = new uint[](_count);
  //   uint index = 0;

  //   if (_cursor == 0)
  //     cursorIndex = 0;
  //   else {
  //     for (uint j = 0; j < betList.length; j++) {
  //       if (betList[j] == _cursor) {
  //         cursorIndex = j;
  //         break;
  //       }
  //     }
  //     require(cursorIndex != 0);
  //   }

  //   for (
  //     uint i = cursorIndex == 0 ? (_oldestFirst ? 0 : 1) : (_oldestFirst ? cursorIndex + 1 : betList.length - cursorIndex + 1);
  //     _oldestFirst ? i < betList.length : i <= betList.length;
  //     i++
  //   ) { // Oldest or newest first.
  //     Bet storage bet = bets[betList[_oldestFirst ? i : betList.length - i]];
  //     Request storage request = bet.requests[bet.requests.length - 1];
  //     if (
  //       /* solium-disable operator-whitespace */
  //       (_filter[0] && bet.status == BetStatus.Absent) ||
  //       (_filter[1] && bet.status == BetStatus.Registered) ||
  //       (_filter[2] && bet.status == BetStatus.RegistrationRequested && !request.disputed) ||
  //       (_filter[3] && bet.status == BetStatus.ClearingRequested && !request.disputed) ||
  //       (_filter[4] && bet.status == BetStatus.RegistrationRequested && request.disputed) ||
  //       (_filter[5] && bet.status == BetStatus.ClearingRequested && request.disputed) ||
  //       (_filter[6] && request.parties[uint(Party.Requester)] == msg.sender) || // My Submissions.
  //       (_filter[7] && request.parties[uint(Party.Challenger)] == msg.sender) // My Challenges.
  //       /* solium-enable operator-whitespace */
  //     ) {
  //       if (index < _count) {
  //         values[index] = betList[_oldestFirst ? i : betList.length - i];
  //         index++;
  //       } else {
  //         hasMore = true;
  //         break;
  //       }
  //     }
  //   }
  // }

  /** @dev Gets the contributions made by a party for a given round of a request.
    *  @param _betID The bet index.
    *  @param _request The position of the request.
    *  @param _round The position of the round.
    *  @param _contributor The address of the contributor.
    *  @return The contributions.
    */
  function getContributions(
    uint _betID,
    uint _request,
    uint _round,
    address _contributor
  ) external view returns(uint[3] memory contributions) {
    Request storage request = bets[_betID].requests[_request];
    Round storage round = request.rounds[_round];
    contributions = round.contributions[_contributor];
  }

  /** @dev Returns bet information. Includes length of requests array.
    *  @param _betID The queried bet index.
    *  @return The bet information.
    */
  function getBetInfo(uint _betID)
    external
    view
    returns (
      BetStatus status,
      uint numberOfRequests
    )
  {
    Bet storage bet = bets[_betID];
    return (
      bet.status,
      bet.requests.length
    );
  }

  /** @dev Gets information on a request made for a bet.
    *  @param _betID The queried bet index.
    *  @param _request The request to be queried.
    *  @return The request information.
    */
  function getRequestInfo(uint _betID, uint _request)
    external
    view
    returns (
      bool disputed,
      uint disputeID,
      uint submissionTime,
      bool resolved,
      address[3] memory parties,
      uint numberOfRounds,
      Party ruling,
      Arbitrator arbitratorRequest,
      bytes memory arbitratorExtraData
    )
  {
    Request storage request = bets[_betID].requests[_request];
    return (
      request.disputed,
      request.disputeID,
      request.submissionTime,
      request.resolved,
      request.parties,
      request.rounds.length,
      request.ruling,
      request.arbitrator,
      request.arbitratorExtraData
    );
  }

  /** @dev Gets the information on a round of a request.
    *  @param _betID The queried bet index.
    *  @param _request The request to be queried.
    *  @param _round The round to be queried.
    *  @return The round information.
    */
  function getRoundInfo(uint _betID, uint _request, uint _round)
    external
    view
    returns (
      bool appealed,
      uint[3] memory paidFees,
      bool[3] memory hasPaid,
      uint feeRewards
    )
  {
    Bet storage bet = bets[_betID];
    Request storage request = bet.requests[_request];
    Round storage round = request.rounds[_round];
    return (
      _round != (request.rounds.length-1),
      round.paidFees,
      round.hasPaid,
      round.feeRewards
    );
  }
}

contract GoalBet is IArbitrable {

  using CappedMath for uint; // Operations bounded between 0 and 2**256 - 1.

  // **************************** //
  // *    Contract variables    * //
  // **************************** //

  struct Bet {
    string description; // alias metaevidence
    uint[3] period; // endBetPeriod, startClaimPeriod, endClaimPeriod
    uint[2] ratio; // For irrational numbers we assume that the loss of wei is negligible
    address[3] parties;
    uint[2] amount; // betterAmount (max), takerTotalAmount
    mapping(address => uint) amountTaker;
    Arbitrator arbitrator;
    bytes arbitratorExtraData;
    uint[3] stakeMultiplier;
    Status status; // Status of the claim relative to a dispute.
    uint disputeID; // If dispute exists, the ID of the dispute.
    Round[] rounds; // Tracks each round of a dispute.
    Party ruling; // The final ruling given, if any.
  }

  struct Round {
    uint[3] paidFees; // Tracks the fees paid by each side on this round.
    bool[3] hasPaid; // True when the side has fully paid its fee. False otherwise.
    uint feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
    mapping(address => uint[3]) contributions; // Maps contributors to their contributions for each side.
  }

  Bet[] public bets;

  // Amount of choices to solve the dispute if needed.
  uint8 constant AMOUNT_OF_CHOICES = 2;

  // Enum relative to different periods in the case of a negotiation or dispute.
  enum Status {NoDispute, WaitingAsker, WaitingTaker, DisputeCreated, Resolved}
  // The different parties of the dispute.
  enum Party {None, Asker, Taker}
  // The different ruling for the dispute resolution.
  enum RulingOptions {NoRuling, AskerWins, TakerWins}

  // One-to-one relationship between the dispute and the bet.
  mapping(address => mapping(uint => uint)) public arbitratorDisputeIDtoBetID;

  // Settings
  address public governor; // The address that can make governance changes to the parameters.
  address public betArbitrableList;

  uint public constant MULTIPLIER_DIVISOR = 10000; // Divisor parameter for multipliers.

  // **************************** //
  // *          Modifier        * //
  // **************************** //

  modifier onlyGovernor {require(msg.sender == address(governor), "The caller must be the governor."); _;}

  // **************************** //
  // *          Events          * //
  // **************************** //

  /** @dev Indicate that a party has to pay a fee or would otherwise be considered as losing.
    * @param _transactionID The index of the transaction.
    * @param _party The party who has to pay.
    */
  event HasToPayFee(uint indexed _transactionID, Party _party);

  /** @dev To be emitted when a party get the rewards or the deposit.
   *  @param _id The index of the bet.
   *  @param _party The party that paid.
   *  @param _amount The amount paid.
   */
  event Reward(uint indexed _id, Party _party, uint _amount);

  /** @dev Emitted when a reimbursements and/or contribution rewards are withdrawn.
    *  @param _id The ID of the bet.
    *  @param _contributor The address that sent the contribution.
    *  @param _round The round from which the reward was taken.
    *  @param _value The value of the reward.
    */
  event RewardWithdrawal(uint indexed _id, address indexed _contributor, uint _round, uint _value);

  /* Constructor */

  /**
    *  @dev Constructs the arbitrable token curated registry.
    *  @param _governor The trusted governor of this contract.
    */
  constructor(
    address _governor
  ) public {
    governor = _governor;
  }

  // **************************** //
  // *    Contract functions    * //
  // *    Modifying the state   * //
  // **************************** //

  function ask(
    string calldata _description,
    uint[3] calldata _period,
    uint[2] calldata _ratio,
    Arbitrator _arbitrator,
    bytes calldata _arbitratorExtraData,
    uint[3] calldata _stakeMultiplier
  ) external payable {
    require(msg.value > 10000);
    require(_ratio[0] > 1);
    require(_ratio[0] > _ratio[1]);
    require(_period[0] > now);
    uint amountXratio1 = msg.value * _ratio[0]; // _ratio0 > (_ratio0/_ratio1)
    require(amountXratio1/msg.value == _ratio[0]); // To prevent multiply overflow.

    Bet storage bet = bets[bets.length++];

    bet.parties[1] = msg.sender;
    bet.description = _description;
    bet.period = _period;
    bet.ratio = _ratio;
    bet.amount = [msg.value, 0];
    bet.arbitrator = _arbitrator;
    bet.arbitratorExtraData = _arbitratorExtraData;
    bet.stakeMultiplier = _stakeMultiplier;
  }

  function take(
    uint _id
  ) external payable {
    require(msg.value > 0);

    Bet storage bet = bets[_id];

    require(now < bet.period[0], "Should bet before the end period bet.");
    require(bet.amount[0] > bet.amount[1]);

    address payable taker = msg.sender;

    // r = bet.ratio[0] / bet.ratio[1]
    // maxAmountToBet = x / (r-1) - y
    // maxAmountToBet = x*x / (rx-x) - y
    uint maxAmountToBet = bet.amount[0]*bet.amount[0] / (bet.ratio[0]*bet.amount[0]/bet.ratio[1] - bet.amount[0]) - bet.amount[1];
    uint amountBet = msg.value <= maxAmountToBet ? msg.value : maxAmountToBet;

    bet.amount[1] += amountBet;
    bet.amountTaker[taker] = amountBet;

    if (msg.value > maxAmountToBet)
      taker.transfer(msg.value - maxAmountToBet);
  }

  function withdraw(
    uint _id
  ) external {
    Bet storage bet = bets[_id];

    require(bet.amount[1] == 0);
    require(now > bet.period[0], "Should end period bet finished.");

    address payable asker = address(uint160(bet.parties[1]));

    asker.send(bet.amount[0]);
    bet.amount[0] = 0;
  }

  /* Section of Claims or Dispute Resolution */

  /** @dev Pay the arbitration fee to claim the bet. To be called by the asker. UNTRUSTED.
    * Note that the arbitrator can have createDispute throw,
    * which will make this function throw and therefore lead to a party being timed-out.
    * This is not a vulnerability as the arbitrator can rule in favor of one party anyway.
    * @param _id The index of the bet.
    */
  function claimAsker(uint _id) public payable {
    Bet storage bet = bets[_id];

    require(
      bet.status < Status.DisputeCreated,
      "Dispute has already been created or because the transaction has been executed."
    );
    require(bet.parties[1] == msg.sender, "The caller must be the creator of the bet.");
    require(now > bet.period[1], "Should claim after the claim period start.");
    require(now < bet.period[2], "Should claim before the claim period end.");

    // Amount required to claim: arbitration cost + (arbitration cost * multiplier).
    uint arbitrationCost = bet.arbitrator.arbitrationCost(bet.arbitratorExtraData);
    uint claimCost = arbitrationCost.addCap((arbitrationCost.mulCap(bet.stakeMultiplier[0])) / MULTIPLIER_DIVISOR);

    // The asker must cover the claim cost.
    require(msg.value >= claimCost);

    if(bet.rounds.length == 0)
      bet.rounds.length++;

    Round storage round = bet.rounds[0];

    round.hasPaid[uint(Party.Asker)] = true;

    contribute(round, Party.Asker, msg.sender, msg.value, claimCost);

    // The taker still has to pay. This can also happen if he has paid,
    // but arbitrationCost has increased.
    if (round.paidFees[uint(Party.Taker)] <= claimCost) {
      bet.status = Status.WaitingTaker;

      emit HasToPayFee(_id, Party.Taker);
    } else { // The taker has also paid the fee. We create the dispute
      raiseDispute(_id, arbitrationCost);
    }
  }

  /** @dev Pay the arbitration fee to claim a bet. To be called by the taker. UNTRUSTED.
    * @param _id The index of the claim.
    */
  function claimTaker(uint _id) public payable {
    Bet storage bet = bets[_id];

    require(
      bet.status < Status.DisputeCreated,
      "Dispute has already been created or because the transaction has been executed."
    );
    // NOTE: We assume that for this smart contract version,
    // this smart contract is vulnerable to a griefing attack.
    // We expect a very low ratio of griefing attack
    // in the majority of cases.
    require(
      bet.amountTaker[msg.sender] > 0,
      "The caller must be the one of the taker."
    );
    require(now > bet.period[1], "Should claim after the claim period start.");
    require(now < bet.period[2], "Should claim before the claim period end.");

    bet.parties[2] = msg.sender;

    // Amount required to claim: arbitration cost + (arbitration cost * multiplier).
    uint arbitrationCost = bet.arbitrator.arbitrationCost(bet.arbitratorExtraData);
    uint claimCost = arbitrationCost.addCap((arbitrationCost.mulCap(bet.stakeMultiplier[0])) / MULTIPLIER_DIVISOR);

    // The taker must cover the claim cost.
    require(msg.value >= claimCost);

    if(bet.rounds.length == 0)
      bet.rounds.length++;

    Round storage round = bet.rounds[0];

    round.hasPaid[uint(Party.Taker)] = true;

    contribute(round, Party.Taker, msg.sender, msg.value, claimCost);

    // The taker still has to pay. This can also happen if he has paid,
    // but arbitrationCost has increased.
    if (round.paidFees[uint(Party.Taker)] <= claimCost) {
      bet.status = Status.WaitingAsker;

      emit HasToPayFee(_id, Party.Taker);
    } else { // The taker has also paid the fee. We create the dispute.
      raiseDispute(_id, arbitrationCost);
    }
  }

  /** @dev Make a fee contribution.
    * @param _round The round to contribute.
    * @param _side The side for which to contribute.
    * @param _contributor The contributor.
    * @param _amount The amount contributed.
    * @param _totalRequired The total amount required for this side.
    */
  function contribute(
    Round storage _round,
    Party _side,
    address payable _contributor,
    uint _amount,
    uint _totalRequired
  ) internal {
    // Take up to the amount necessary to fund the current round at the current costs.
    uint contribution; // Amount contributed.
    uint remainingETH; // Remaining ETH to send back.

    (contribution, remainingETH) = calculateContribution(_amount, _totalRequired.subCap(_round.paidFees[uint(_side)]));
    _round.contributions[_contributor][uint(_side)] += contribution;
    _round.paidFees[uint(_side)] += contribution;
    _round.feeRewards += contribution;

    // Reimburse leftover ETH.
    _contributor.send(remainingETH); // Deliberate use of send in order to not block the contract in case of reverting fallback.
  }

  /** @dev Returns the contribution value and remainder from available ETH and required amount.
    * @param _available The amount of ETH available for the contribution.
    * @param _requiredAmount The amount of ETH required for the contribution.
    * @return taken The amount of ETH taken.
    * @return remainder The amount of ETH left from the contribution.
    */
  function calculateContribution(uint _available, uint _requiredAmount)
    internal
    pure
    returns(uint taken, uint remainder)
  {
    if (_requiredAmount > _available)
      return (_available, 0); // Take whatever is available, return 0 as leftover ETH.

    remainder = _available - _requiredAmount;

    return (_requiredAmount, remainder);
  }

  /** @dev Reward asker of the bet if the taker fails to pay the fee.
    * NOTE: The taker unspent fee are sent to the asker.
    * @param _id The index of the bet.
    */
  function timeOutByAsker(uint _id) public {
    Bet storage bet = bets[_id];

    require(
      bet.status == Status.WaitingTaker,
      "The transaction of the bet must waiting on the taker."
    );
    require(
      now > bet.period[2],
      "Timeout claim has not passed yet."
    );

    uint resultRuling = uint(RulingOptions.AskerWins);
    bet.ruling = Party(resultRuling);

    executeRuling(_id, resultRuling);
  }

  /** @dev Pay taker if the asker fails to pay the fee.
    * NOTE: The asker unspent fee are sent to the taker.
    * @param _id The index of the claim.
    */
  function timeOutByTaker(uint _id) public {
    Bet storage bet = bets[_id];

    require(
      bet.status == Status.WaitingAsker,
      "The transaction of the bet must waiting on the asker."
    );
    require(
      now > bet.period[2],
      "Timeout claim has not passed yet."
    );

    uint resultRuling = uint(RulingOptions.TakerWins);
    bet.ruling = Party(resultRuling);

    executeRuling(_id, resultRuling);
  }

  /** @dev Create a dispute. UNTRUSTED.
    * @param _id The index of the bet.
    * @param _arbitrationCost Amount to pay the arbitrator.
    */
  function raiseDispute(uint _id, uint _arbitrationCost) internal {
    Bet storage bet = bets[_id];

    bet.status = Status.DisputeCreated;
    uint disputeID = bet.arbitrator.createDispute.value(_arbitrationCost)(AMOUNT_OF_CHOICES, bet.arbitratorExtraData);
    arbitratorDisputeIDtoBetID[address(bet.arbitrator)][disputeID] = _id;
    bet.disputeID = disputeID;

    emit Dispute(bet.arbitrator, bet.disputeID, _id, _id);
  }

  /** @dev Submit a reference to evidence. EVENT.
    * @param _id The index of the claim.
    * @param _evidence A link to an evidence using its URI.
    */
  function submitEvidence(uint _id, string memory _evidence) public {
    Bet storage bet = bets[_id];

    require(
      msg.sender == bet.parties[1] || bet.amountTaker[msg.sender] > 0,
      "The caller must be the asker or a taker."
    );
    require(
      bet.status >= Status.DisputeCreated,
      "The dispute has not been created yet."
    );

    emit Evidence(bet.arbitrator, _id, msg.sender, _evidence);
  }

  /** @dev Takes up to the total amount required to fund a side of an appeal. Reimburses the rest. Creates an appeal if both sides are fully funded. TRUSTED.
    * @param _id The ID of the bet with the request to fund.
    * @param _side The recipient of the contribution.
    */
  function fundAppeal(uint _id, Party _side) external payable {
    // Recipient must be either the requester or challenger.
    require(_side == Party.Asker || _side == Party.Taker); // solium-disable-line error-reason

    Bet storage bet = bets[_id];

    require(
      bet.status >= Status.DisputeCreated,
      "A dispute must have been raised to fund an appeal."
    );

    (uint appealPeriodStart, uint appealPeriodEnd) = bet.arbitrator.appealPeriod(bet.disputeID);

    require(
      now >= appealPeriodStart && now < appealPeriodEnd,
      "Contributions must be made within the appeal period."
    );

    Round storage round = bet.rounds[bet.rounds.length - 1];

    Party winner = Party(bet.arbitrator.currentRuling(bet.disputeID));
    Party loser;

    if (winner == Party.Asker)
        loser = Party.Taker;
    else if (winner == Party.Taker)
        loser = Party.Asker;

    require(!(_side==loser) || (now-appealPeriodStart < (appealPeriodEnd-appealPeriodStart)/2), "The loser must contribute during the first half of the appeal period.");

    uint multiplier;

    if (_side == winner)
        multiplier = bet.stakeMultiplier[1];
    else if (_side == loser)
        multiplier = bet.stakeMultiplier[2];
    else
        multiplier = bet.stakeMultiplier[0];

    uint appealCost = bet.arbitrator.appealCost(bet.disputeID, bet.arbitratorExtraData);
    uint totalCost = appealCost.addCap((appealCost.mulCap(multiplier)) / MULTIPLIER_DIVISOR);

    contribute(round, _side, msg.sender, msg.value, totalCost);

    if (round.paidFees[uint(_side)] >= totalCost)
      round.hasPaid[uint(_side)] = true;

    // Raise appeal if both sides are fully funded.
    if (round.hasPaid[uint(Party.Taker)] && round.hasPaid[uint(Party.Asker)]) {
      bet.arbitrator.appeal.value(appealCost)(bet.disputeID, bet.arbitratorExtraData);
      bet.rounds.length++;
      round.feeRewards = round.feeRewards.subCap(appealCost);
    }
  }

  /** @dev Give a ruling for a dispute. Must be called by the arbitrator.
    * The purpose of this function is to ensure that the address calling it has the right to rule on the contract.
    * @param _disputeID ID of the dispute in the Arbitrator contract.
    * @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Not able/wanting to make a decision".
    */
  function rule(uint _disputeID, uint _ruling) external {
    Party resultRuling = Party(_ruling);
    uint id = arbitratorDisputeIDtoBetID[msg.sender][_disputeID];

    Bet storage bet = bets[id];

    require(_ruling <= AMOUNT_OF_CHOICES); // solium-disable-line error-reason
    require(address(bet.arbitrator) == msg.sender); // solium-disable-line error-reason
    require(bet.status != Status.Resolved); // solium-disable-line error-reason

    Round storage round = bet.rounds[bet.rounds.length - 1];

    // The ruling is inverted if the loser paid its fees.
    // If one side paid its fees, the ruling is in its favor. 
    // Note that if the other side had also paid, an appeal would have been created.
    if (round.hasPaid[uint(Party.Asker)] == true)
      resultRuling = Party.Asker;
    else if (round.hasPaid[uint(Party.Taker)] == true)
      resultRuling = Party.Taker;

    bet.status = Status.Resolved;
    bet.ruling = resultRuling;

    emit Ruling(Arbitrator(msg.sender), _disputeID, uint(resultRuling));

    executeRuling(id, uint(resultRuling));
  }

  /** @dev Reimburses contributions if no disputes were raised. 
    * If a dispute was raised, sends the fee stake and the reward for the winner.
    * @param _beneficiary The address that made contributions to a request.
    * @param _id The ID of the bet.
    * @param _round The round from which to withdraw.
    */
  function withdrawFeesAndRewards(
    address payable _beneficiary, 
    uint _id, 
    uint _round
  ) public {
    Bet storage bet = bets[_id];
    Round storage round = bet.rounds[_round];
    // The request must be resolved.
    require(bet.status == Status.Resolved); // solium-disable-line error-reason

    uint reward;

    if (bet.ruling == Party.None) {
      // No disputes were raised, or there isn't a winner and loser. Reimburse unspent fees proportionally.
      uint rewardAsker = round.paidFees[uint(Party.Asker)] > 0
        ? (round.contributions[_beneficiary][uint(Party.Asker)] * round.feeRewards) / (round.paidFees[uint(Party.Taker)] + round.paidFees[uint(Party.Asker)])
        : 0;
      uint rewardTaker = round.paidFees[uint(Party.Taker)] > 0
        ? (round.contributions[_beneficiary][uint(Party.Taker)] * round.feeRewards) / (round.paidFees[uint(Party.Taker)] + round.paidFees[uint(Party.Asker)])
        : 0;

      reward = rewardAsker + rewardTaker;
      round.contributions[_beneficiary][uint(Party.Asker)] = 0;
      round.contributions[_beneficiary][uint(Party.Taker)] = 0;

      // Reimburse the fund bet.
      if(bet.amountTaker[_beneficiary] > 0) {
        reward += bet.amountTaker[_beneficiary];
        bet.amountTaker[_beneficiary] = 0;
      }
    } else {
      // Reward the winner.
      reward = round.paidFees[uint(bet.ruling)] > 0
        ? (round.contributions[_beneficiary][uint(bet.ruling)] * round.feeRewards) / round.paidFees[uint(bet.ruling)]
        : 0;

      round.contributions[_beneficiary][uint(bet.ruling)] = 0;

      if(bet.amountTaker[_beneficiary] > 0 && bet.ruling != Party.Asker) {
        reward += bet.amountTaker[_beneficiary] * bet.ratio[0] / bet.ratio[1];
        bet.amountTaker[_beneficiary] = 0;
      }
    }

    emit RewardWithdrawal(_id, _beneficiary, _round,  reward);

    _beneficiary.send(reward); // It is the user responsibility to accept ETH.
  }

  /** @dev Execute a ruling of a dispute. It reimburses the fee to the winning party.
    * @param _id The index of the bet.
    * @param _ruling Ruling given by the arbitrator. 1 : Reimburse the owner of the item. 2 : Pay the finder.
    */
  function executeRuling(uint _id, uint _ruling) internal {
    require(_ruling <= AMOUNT_OF_CHOICES, "Invalid ruling.");

    Bet storage bet = bets[_id];

    bet.status = Status.Resolved;

    address payable asker = address(uint160(bet.parties[1]));
    address payable taker = address(uint160(bet.parties[2]));

    if (_ruling == uint(Party.None)) {
      if(bet.amount[0] > 0) {
        asker.send(bet.amount[0]);
        bet.amount[0] = 0;
      }

      withdrawFeesAndRewards(asker, _id, 0);
      withdrawFeesAndRewards(taker, _id, 0);
    } else if (_ruling == uint(Party.Asker)) {
      require(bet.amount[0] > 0);

      asker.send(bet.amount[0] + bet.amount[1]);

      bet.amount[0] = 0;
      bet.amount[1] = 0;

      withdrawFeesAndRewards(asker, _id, 0);
    } else {
      withdrawFeesAndRewards(taker, _id, 0);
    }
  }


  /* Governance */

  /** @dev Change the governor of the token curated registry.
    *  @param _governor The address of the new governor.
    */
  function changeGovernor(address _governor) external onlyGovernor {
    governor = _governor;
  }

  /** @dev Change the address of the goal bet registry contract.
  *  @param _betArbitrableList The address of the new goal bet registry contract.
  */
  function changeArbitrationBetList(address _betArbitrableList) external onlyGovernor {
    betArbitrableList = _betArbitrableList;
  }

  // **************************** //
  // *     View functions       * //
  // **************************** //

  /** @dev Get the claim cost
    * @param _id The index of the claim.
    */
  function getClaimCost(uint _id)
    external
    view
    returns (uint claimCost)
  {
    Bet storage bet = bets[_id];

    uint arbitrationCost = bet.arbitrator.arbitrationCost(bet.arbitratorExtraData);
    claimCost = arbitrationCost.addCap((arbitrationCost.mulCap(bet.stakeMultiplier[0])) / MULTIPLIER_DIVISOR);
  }

  function getMaxAmountToBet(
    uint _id
  ) external view returns (uint maxAmountToBet) {
    Bet storage bet = bets[_id];

    maxAmountToBet = bet.amount[0]*bet.amount[0] / (bet.ratio[0]*bet.amount[0] / bet.ratio[1] - bet.amount[0]) - bet.amount[1];
  }
}
