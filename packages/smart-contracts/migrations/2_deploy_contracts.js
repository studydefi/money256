const { ethers } = require('ethers')
const PricelessCFD = artifacts.require("PricelessCFD");

module.exports = function(deployer) {
  deployer.deploy(
    PricelessCFD,
    ethers.utils.parseEther("5"), // Leverage
    ethers.utils.parseEther("0.01"), // Fee
    parseInt(Date.now() / 1000) + 2592000, // One month from now
    ethers.utils.parseEther("1"), // Arbitrary price of asset we're tracking
    ethers.utils.parseEther("0.2"), // Ceil is 1.2 and bottom is 0.8
    600, // 10 minute window before mint request gets mined
    { gas: 6000000 }
  );
};
