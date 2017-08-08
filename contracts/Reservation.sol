pragma solidity ^0.4.11;

import "./imported/openzeppelin/SafeMath.sol";
import "./imported/ethereum/Wallet.sol";
import "./MultisigLogic/MultisigLogic.sol";

contract Reservation {
  using SafeMath for uint256;

  Wallet wallet;
  MultisigLogic multisigLogic;

  enum State { Initial, Deposit, Completed, Contribution, Refund, Emergency, End }
  State public state;

  struct DepositDetails {
    uint etherDeposited;
    bool etherRefunded;
    uint dgxContributed;
  }

  mapping (address => bool) public whitelist;
  mapping (address => DepositDetails) public registrations;

  address public whitelister;
  address public fundraiser;
  uint public depositStartTime;
  uint public minETHDeposit;
  uint public multipleETHDeposit;
  uint public maxETHDepositTotal;
  uint public maxETHDepositPerAcct;
  uint public dgxPerMinETHDeposit;
  uint public totalEtherDeposited;
  uint public totalEtherForfeited;
  uint public totalEtherRefunded;
  uint public totalEtherEmergencyRefunded;

  event EtherDeposited(uint blockNumber, address indexed depositor, uint amount);
  event EtherRefunded(uint blockNumber, address indexed depositor, uint amount);
  event EtherImmediateRefund(uint blockNumber, address indexed depositor, uint amount);

  /**
   * @dev Constuctor, setting up the contract.
   * @param _wallet the forwarding wallet address.
   * @param _logic the multisig logic.
   */
  function Reservation(address _wallet, address _logic) {
    wallet = Wallet(_wallet);
    multisigLogic = MultisigLogic(_logic);

//    depositStartTime = 1501509600; // 07/31/2017 @ 2:00pm (UTC)
    depositStartTime = 1500904800; // 07/24/2017 @ 2:00pm (UTC)
    minETHDeposit = 2 * 1 ether;
    multipleETHDeposit = 2 * 1 ether;
    maxETHDepositTotal = 1612 * 1 ether;
    maxETHDepositPerAcct = 100 * 1 ether;
    dgxPerMinETHDeposit = 100 * 10**9;

    whitelister = msg.sender;
    fundraiser = msg.sender;

    // sets Initial state.
    state = State.Initial;
  }

  /**
   * @dev payable fallback function, called when contributor sends ETH (with or without value) to the contract.
   */
  function () external payable {
    if (msg.value>0) {
      if (state==State.Initial && now >= depositStartTime) {
        state == State.Deposit;
      }
      deposit(msg.sender, msg.value);
    } else {
      if (state == State.Refund) {
        refund(msg.sender);
      } else if (state == State.Emergency){
        emergencyRefund(msg.sender);
      } else {
        throw;
      }
    }
  }

  /**
   * @dev Entry point of `_amount` ETH deposit from `_contributor`. It should meet the min ETH deposit amount,
   * within deposit period, in deposit state.
   * @param _contributor address The address of contributor.
   * @param _amount uint The ETH deposit amount.
   */
  function deposit(address _contributor, uint _amount) internal depositState hasMinEtherDeposit {
    require(!isContract(_contributor));
    require(isInWhitelist(_contributor));

    // accepts only in multiple of depositMultiple ETH. refunds the rest.
    uint acceptedAmount = _amount.div(multipleETHDeposit).mul(multipleETHDeposit);
    uint refundAmount = _amount % multipleETHDeposit;

    // accepts only as per cap per account, refunds the rest.
    uint remainingDepositAllowedPerAcct = maxETHDepositPerAcct.sub(registrations[_contributor].etherDeposited);
    if (remainingDepositAllowedPerAcct < acceptedAmount) {
      refundAmount = refundAmount.add(acceptedAmount.sub(remainingDepositAllowedPerAcct));
      acceptedAmount = remainingDepositAllowedPerAcct;
    }

    // accepts only as per cap in total, refunds the rest.
    uint remainingDepositAllowedTotal = maxETHDepositTotal.sub(totalEtherDeposited);
    if (remainingDepositAllowedTotal < acceptedAmount) {
      refundAmount = refundAmount.add(acceptedAmount.sub(remainingDepositAllowedTotal));
      acceptedAmount = remainingDepositAllowedTotal;
    }

    if (acceptedAmount>0) {
      registrations[_contributor].etherDeposited = registrations[_contributor].etherDeposited.add(acceptedAmount);
      totalEtherDeposited = totalEtherDeposited.add(acceptedAmount);
      totalEtherForfeited = totalEtherForfeited.add(acceptedAmount);
      EtherDeposited(block.number, _contributor, acceptedAmount);

      if (totalEtherDeposited == maxETHDepositTotal) {
        state = State.Completed;
      }
    }
    if (refundAmount > 0) {
      _contributor.transfer(refundAmount);
      EtherImmediateRefund(block.number, _contributor, refundAmount);
    }
  }

  /**
   * @dev Entry point of ETH emergency refund to `_contributor`, if eligible.
   * Eligibility:
   * a. it is in the whitelist (by way of joining reservation and verify email address), and
   * b. it has contributed DGX (during the early-access fundraising period), and
   * c. it hasn't had its ETH refunded
   * @param _contributor address The address of contributor.
   */
  function refund(address _contributor) internal refundState {
    require(!isContract(_contributor));
    require(isInWhitelist(_contributor));
    require(registrations[_contributor].dgxContributed > 0);
    require(registrations[_contributor].etherRefunded == false);
    processRefund(_contributor);
  }

  /**
   * @dev Entry point of ETH emergency refund to `_contributor`, if eligible.
   * Eligibility:
   * a. it is in the whitelist (by way of joining reservation and verify email address), and
   * b. it hasn't had its ETH refunded
   * @param _contributor address The address of contributor.
   */
  function emergencyRefund(address _contributor) internal emergencyState {
    require(!isContract(_contributor));
    require(isInWhitelist(_contributor));
    require(registrations[_contributor].etherRefunded == false);
    processRefund(_contributor);
  }

  /**
   * @dev Processes `_contributor` ETH refund.
   * @param _contributor address The address of contributor.
   */
  function processRefund(address _contributor) internal {
    uint depositAmount = getDepositAmount(_contributor);
    require(this.balance >= depositAmount);
    registrations[_contributor].etherRefunded = true;
    totalEtherForfeited = totalEtherForfeited.sub(depositAmount);
    if (state == State.Refund) {
      if ((depositAmount.div(minETHDeposit)).mul(dgxPerMinETHDeposit) < registrations[_contributor].dgxContributed) {
        throw;
      } else {
        totalEtherRefunded = totalEtherRefunded.add(depositAmount);
      }
    } else if (state == State.Emergency) {
      totalEtherEmergencyRefunded = totalEtherEmergencyRefunded.add(depositAmount);
    }
    _contributor.transfer(depositAmount);
    EtherRefunded(block.number, _contributor, depositAmount);
  }

  /**
   * @dev Determines if `_addr` is a contract address.
   * @param _addr address The address being queried.
   */
  function isContract(address _addr) constant internal returns (bool) {
    if (_addr == 0) return false;
    uint256 size;
    assembly {
      size := extcodesize(_addr)
    }
    return (size > 0);
  }

  /**
   * @dev Allows whitelister to add `_contributor` to the whitelist.
   * @param _contributor address The address of contributor.
   */
  function addToWhitelist(address _contributor) whitelisterOnly {
    whitelist[_contributor] = true;
  }

  /**
   * @dev Allows authorized signatories to remove `_contributor` from the whitelist.
   * @param _contributor address The address of contributor.
   */
  function removeFromWhitelist(address _contributor) internal {
    whitelist[_contributor] = false;
  }

  /**
   * @dev Checks if `_contributor` is in the whitelist.
   * @param _contributor address The address of contributor.
   */
  function isInWhitelist(address _contributor) constant returns (bool) {
    return (whitelist[_contributor] == true);
  }

  /**
   * @dev Marks DGX contribution for `_contributor` with amount `_amount`.
   * @param _contributor address The address of contributor.
   */
  function markDgxContribution(address _contributor, uint _amount) fundraiserOnly contributionState {
    require(isInWhitelist(_contributor));
    registrations[_contributor].dgxContributed = registrations[_contributor].dgxContributed.add(_amount);
  }

  /**
   * @dev Retrieves `_contributor` deposit amount.
   * @param _contributor address The address of contributor.
   */
  function getDepositAmount(address _contributor) constant returns (uint) {
    return registrations[_contributor].etherDeposited;
  }

  /**
   * @dev Retrieves `_contributor` contribution amount of dgx.
   * @param _contributor address The address of contributor.
   */
  function getDgxContributionAmount(address _contributor) constant returns (uint) {
    return registrations[_contributor].dgxContributed;
  }

  /**
   * @dev Allows authorized callers to transfer all remaining Ether to MultisigWallet, after multisig approvals.
   * @param _h bytes32 the hash of multisig operation.
   */
  function sendAllEther(bytes32 _h) apo {
    bytes32 _hash;
    bool _status;
    (_hash, _status) = multisigLogic.executeOrConfirm(msg.sender, _h);
    if (_status) {
      MultiSigOpsStatus("Confirmed", _hash);
      wallet.transfer(this.balance);
    } else {
      MultiSigOpsStatus("ConfirmationNeeded", _hash);
    }
  }

  /**
   * @dev Allows authorized signatories to update contributor address.
   * @param _old address the old contributor address.
   * @param _new address the new contributor address.
   */
  function updateContributorAddress(address _old, address _new) apo {
    require(isContract(_new));
    removeFromWhitelist(_old);
    addToWhitelist(_new);
    registrations[_new].etherDeposited  = registrations[_old].etherDeposited;
    registrations[_new].etherRefunded  = registrations[_old].etherRefunded;
    registrations[_new].dgxContributed  = registrations[_old].dgxContributed;
    registrations[_old].etherDeposited = 0;
    registrations[_old].etherRefunded = false;
    registrations[_old].dgxContributed = 0;
  }

  /**
   * @dev Allows authorized signatories to update `_new` as new whitelister.
   * @param _new address The address of new whitelister.
   */
  function updateWhitelister(address _new) apo {
    whitelister = _new;
  }
  /**
   * @dev Allows authorized signatories to update `_new` as new fundraiser.
   * @param _new address The address of new fundraiser.
   */
  function updateFundraiser(address _new) apo {
    fundraiser = _new;
  }

  /// @dev activate state
  function setStateDeposit() apo { state = State.Deposit; }
	function setStateCompleted() apo { state = State.Completed; }
  function setStateContribution() apo { state = State.Contribution; }
  function setStateRefund() apo { state = State.Refund; }
  function setStateEmergency(bytes32 _h) apo {
    bytes32 _hash;
    bool _status;
    (_hash, _status) = multisigLogic.executeOrConfirm(msg.sender, _h);
    if (_status) {
      MultiSigOpsStatus("Confirmed", _hash);
      state = State.Emergency;
    } else {
      MultiSigOpsStatus("ConfirmationNeeded", _hash);
    }
  }
  function setStateEnd() apo { state = State.End; }

  /// @dev state modifiers
  modifier depositState() { require(state == State.Deposit); _; }
  modifier completedState() { require(state == State.Completed); _; }
  modifier contributionState() { require(state == State.Contribution); _; }
  modifier refundState() { require((state == State.Refund) || (state == State.Contribution)); _; }
  modifier emergencyState() { require(state == State.Emergency); _; }

  /**
   * @dev Modifier that throws if ETH sent does not meet the min ETH deposit amount.
   */
  modifier hasMinEtherDeposit {
    require(msg.value>=minETHDeposit);
    _;
  }

  /**
   * @dev Modifier that throws if sender is not whitelister.
   */
  modifier whitelisterOnly {
    require(msg.sender == whitelister);
    _;
  }

  /**
   * @dev Modifier that throws if sender is not fundraiser.
   */
  modifier fundraiserOnly {
    require(msg.sender == fundraiser);
    _;
  }

  /**
   * @dev Modifier that throws if senders are not authorized.
   */
  modifier apo {
    require(multisigLogic.isOwner(msg.sender));
    _;
  }

  event MultiSigOpsStatus(string status, bytes32 msg);
}
