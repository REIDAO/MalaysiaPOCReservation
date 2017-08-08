var Wallet                    = artifacts.require("./imported/ethereum/Wallet.sol");
var MultisigLogic             = artifacts.require("./MultisigLogic.sol");
var Reservation               = artifacts.require("./Reservation.sol");

var Signatories               = require('fs').readFileSync("../../key/signatories.sig", 'utf-8').split('\n').filter(Boolean);
var RequiredSignatories       = 2;

module.exports = function(deployer, network, accounts)
{
  deployer.deploy(Wallet, Signatories, RequiredSignatories, 2 * Math.pow(10,18), 1 * Math.pow(10,18))
  .then(function() {
    return deployer.deploy(MultisigLogic, Signatories, RequiredSignatories);
  })
  .then(function() {
    return deployer.deploy(Reservation, Wallet.address, MultisigLogic.address);
  })
  ;
};
