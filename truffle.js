//e.g.
//truffle migrate --reset --network live
//truffle migrate --reset --network rinkeby
//truffle migrate --reset --network ropsten

var fs = require("fs");
var path = require("path");

var bip39 = require("bip39");
var hdkey = require('ethereumjs-wallet/hdkey');
var ProviderEngine = require("web3-provider-engine");
var WalletSubprovider = require('web3-provider-engine/subproviders/wallet.js');
var Web3Subprovider = require("web3-provider-engine/subproviders/web3.js");
var Web3 = require("web3");

var mnemonicSeeds = fs.readFileSync(path.join("../key", "mnemonic.seeds"), {encoding: "utf8"}).trim();
var mnemonicIndex = fs.readFileSync(path.join("../key", "index.key"), {encoding: "utf8"}).trim();
var infuraKey = fs.readFileSync(path.join("../key", "infura.key"), {encoding: "utf8"}).trim();

var url = "";
var action = process.argv[2];
if (action == "migrate") {
  var network = process.argv[5];
  if (network == "live")
    url = "https://mainnet.infura.io/";
  else if (network == "rinkeby")
    url = "https://rinkeby.infura.io/";
  else if (network == "ropsten")
    url = "https://ropsten.infura.io/";

  url = url + infuraKey;

  var hdwallet = hdkey.fromMasterSeed(bip39.mnemonicToSeed(mnemonicSeeds));
  var wallet_hdpath_metamask = "m/44'/60'/0'/0/";
  var wallet_hdpath_ledger = "m/44'/60'/0'/";
  var wallet_hdpath = wallet_hdpath_ledger;
  var wallet = hdwallet.derivePath(wallet_hdpath + mnemonicIndex).getWallet();
  var address = "0x" + wallet.getAddress().toString("hex");
  console.log("Deploying at " + url + ", by " + address);

  var providerInstance = new ProviderEngine();
  providerInstance.addProvider(new WalletSubprovider(wallet, {}));
  providerInstance.addProvider(new Web3Subprovider(new Web3.providers.HttpProvider(url)));
  providerInstance.start(); // Required by the provider engine.
}
var gasPrice = 20000000000;
var gasLimit = 4712388;

module.exports = {
  networks: {
    live: {
      provider: providerInstance,
      network_id: 1,
      gasPrice: gasPrice,
      gas: gasLimit
    },
    rinkeby: {
      provider: providerInstance,
      network_id: 4,
      gasPrice: gasPrice,
      gas: gasLimit
    },
    ropsten: {
      provider: providerInstance,
      network_id: 3,
      gasPrice: gasPrice,
      gas: gasLimit
    },
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    }
  },
  rpc: {
    // Use the default host and port when not using ropsten
    host: "localhost",
    port: 8545
  }
};
