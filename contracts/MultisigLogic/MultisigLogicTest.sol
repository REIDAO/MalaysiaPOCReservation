pragma solidity ^0.4.11;

import "./MultisigLogic.sol";

contract MultisigLogicTest {

  MultisigLogic multisigLogic;

  function MultisigLogicTest(address _multisigLogic) {
    multisigLogic = MultisigLogic(_multisigLogic);
  }

  function callHello(bytes32 _h) {
    bytes32 _hash;
    bool _status;
    (_hash, _status) = multisigLogic.executeOrConfirm(msg.sender, _h);
    if (_status) {
      Hello("MultisigLogicTest - SUCCESSFUL");
    } else {
      ConfirmationNeeded(_hash);
    }
  }

  event Hello(string msg);
  event ConfirmationNeeded(bytes32 msg);
}
