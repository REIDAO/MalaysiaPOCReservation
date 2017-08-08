/* TEST DATA - START */
//testing for emergency refund. To be updated with multisig testing for setStateEmergency
//Run with `testrpc -a 25`
//accounts[0] = deployer, multisig
//accounts[1,2] = multisig
//accounts[3] = 2 etherDeposited
//accounts[4] = 10 etherDeposited
//accounts[5..20] = 100 etherDeposited each, total is 1612 ether
//accounts[21..22] = donator accounts, distributed 10 ETH each to acct [5..20]
//accounts[23] = extra account, whitelisted, but not able to participant due to fully subscribed.
//accounts[24] = extra account, not whitelisted, hence not able to participant
var loggingEnabled = true;

var Wallet                    = artifacts.require("./imported/ethereum/Wallet.sol");
var MultisigLogic             = artifacts.require("./MultisigLogic.sol");
var Reservation               = artifacts.require("./Reservation.sol");

var ReservationInstance;
var WalletInstance;

contract('All', function(accounts) {
  it("Reservation - Deployment successful", function() {
    return Reservation.deployed()
    .then(function(result) {
      ReservationInstance = result;
      console.log("reservation: " + result.address);
      assert.isNotNull(result.address, "Address is not empty: " + result.address);
    });
  });

  it("Wallet - Deployment successful", function() {
    return Wallet.deployed()
    .then(function(result) {
      WalletInstance = result;
      console.log("wallet: " + result.address);
      assert.isNotNull(result.address, "Address is not empty: " + result.address);
    });
  });

  it("Check state - Should be Initial", function() {
    return ReservationInstance.state.call()
    .then(function(result) {
      assert.equal(result.valueOf(), 0);
    })
    ;
  });

  it("Account idx 21 transfer 10 ETH each to acct idx 5 to 12", function() {
    for (var i=5; i<=12; i++) {
      web3.eth.sendTransaction({from:accounts[21], to:accounts[i], value: 10 * Math.pow(10,18)})
    }
  });
  it("Account idx 22 transfer 10 ETH each to acct idx 13 to 20", function() {
    for (var i=13; i<=20; i++) {
      web3.eth.sendTransaction({from:accounts[22], to:accounts[i], value: 10 * Math.pow(10,18)})
    }
  });

  it("Deposit 1 (2 ether) - Failed transfer due to not in whitelist yet", function() {
    return ReservationInstance.addToWhitelist(accounts[4])
    .then(function(result) {
      return web3.eth.sendTransaction({from:accounts[3], to:ReservationInstance.address, value: 2 * Math.pow(10,18)})
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  });

  it("Deposit 1 (2 ether) - Failed transfer due to not in not started yet", function() {
    return ReservationInstance.addToWhitelist(accounts[3])
    .then(function(result) {
      return web3.eth.sendTransaction({from:accounts[3], to:ReservationInstance.address, value: 2 * Math.pow(10,18)})
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  });

  it("Deposit 1 (1 ether) - Failed transfer due to transfer less than 2 ether", function() {
    return ReservationInstance.setStateDeposit()
    .then(function(result) {
      return web3.eth.sendTransaction({from:accounts[3], to:ReservationInstance.address, value: 1 * Math.pow(10,18)})
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  });

  it("Deposit 1 (2 ether) - Successful since it has started, account in whitelist, and transfer >= 2 ether", function() {
    web3.eth.sendTransaction({from:accounts[3], to:ReservationInstance.address, value: 2 * Math.pow(10,18), gas: 150000});
  })

  it("Deposit 1 - Check correct balance (2 ether)", function() {
    var result = web3.eth.getBalance(ReservationInstance.address);
    assert.equal(result, 2 * Math.pow(10,18));
  });

  it("Deposit 2 (10 ether) - Successful since it has started, account in whitelist, and transfer >= 2 ether", function() {
    web3.eth.sendTransaction({from:accounts[4], to:ReservationInstance.address, value: 10 * Math.pow(10,18), gas: 150000});
  })

  it("Deposit 2 - Check correct balance (12 ether)", function() {
    var result = web3.eth.getBalance(ReservationInstance.address);
    assert.equal(result, 12 * Math.pow(10,18));
  });

  it("Add 17 accounts to whitelist", function() {
    for (var i=5; i<=21; i++) {
      ReservationInstance.addToWhitelist(accounts[i]).then(function() {
      });
    }
  });
  it("16 accounts deposit 101 ETH to the contract", function() {
    for (var i=5; i<=20; i++) {
      web3.eth.sendTransaction({from:accounts[i], to:ReservationInstance.address, value: 101 * Math.pow(10,18), gas: 150000})
    }
  });

  it("Deposit 3 - Check correct balance (1612 ether)", function() {
    var result = web3.eth.getBalance(ReservationInstance.address);
    assert.equal(result, 1612 * Math.pow(10,18));
  });

  it("DGXContribution 1 - Mark DGX Contribution from accounts not whitelisted. Failed due to not in Contribution Stage.", function() {
    return ReservationInstance.markDgxContribution(accounts[24])
    .then(function(result) {
      //should not come here.
      return true;
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  })

  it("DGXContribution 1 - Mark DGX Contribution from accounts not whitelisted. Failed due to account not whitelisted.", function() {
    return ReservationInstance.setStateContribution()
    .then(function(result) {
      return ReservationInstance.markDgxContribution(accounts[24], 1000000000)
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  })

  it("DGXContribution 2 - Mark DGX Contribution from accounts whitelisted. Success due to account whitelisted.", function() {
    return ReservationInstance.markDgxContribution(accounts[3], 1000000000)
    .then(function(result) {
      return ReservationInstance.registrations(accounts[3])
    })
    .then(function(result) {
      assert.equal(1000000000, result[2].valueOf());
    })
    ;
  })

  it("Refund failed due to not in any refund mode", function() {
    return ReservationInstance.setStateContribution()
    .then(function(result) {
      return web3.eth.sendTransaction({from:accounts[3], to:ReservationInstance.address, value: 0, gas: 150000})
    })
    .catch(function(err) {
      assert(true, err.toString().indexOf("invalid opcode")!=-1);
    })
    ;
  });

  it("Send all Ether", function() {
    return ReservationInstance.sendAllEther("", {from:accounts[1]})
    .then(function(result) {
      var event = ReservationInstance.MultiSigOpsStatus();
      var counter=0;
      event.watch(function(error, result) {
        if (result) {
          counter++;
          if (counter==1) {
            console.log("event1=" + result.args.status);
            console.log("event1=" + result.args.msg);
            ReservationInstance.sendAllEther(result.args.msg, {from:accounts[2]});
          } else {
            console.log("event2=" + result.args.status);
            console.log("event2=" + result.args.msg);
            event.stopWatching();
            var result = web3.eth.getBalance(WalletInstance.address);
            assert.equal(result.valueOf(), 1612 * Math.pow(10,18));
          }
        }
      });
    });
  });

});

function log(msg)
{
  if (loggingEnabled)
    console.log(msg);
}
