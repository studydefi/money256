require('dotenv').config({ path: '../../.env' });
const { ethers } = require("ethers");
// const { legos } = require("@studydefi/money-legos");
// const Promise = require("bluebird");

// Contract definitions
const pricelessCFDDef = require("money256-smart-contracts/build/PricelessCFD.json");
// const identifierWhitelistDef = require("money256-smart-contracts/build/IdentifierWhitelist.json");
// const finderDef = require("money256-smart-contracts/build/Finder.json");
// const bPoolDef = require("money256-smart-contracts/build/IBPool.json");
// const tokenDef = require("money256-smart-contracts/build/Token.json");

const provider = new ethers.providers.JsonRpcProvider(
  process.env.PROVIDER_URL || "http://localhost:8545"
);

const wallet = new ethers.Wallet(
  process.env.PK_GENERIC_1,
  provider
);

// Function to get current price of asset
const getAssetPrice = async () => {
  // TODO: Make this an API call to get the right price
  return ethers.utils.parseEther("1.02");
};

// Pub/Sub events
const pricelessCFDContract = new ethers.Contract(
  pricelessCFDDef.networks["1"].address,
  pricelessCFDDef.abi,
  wallet
);

// Only start listening to latest block events
const setupSettleRequestListener = async () => {
  // Settle Event Listener
  const settleRequestedFilter = pricelessCFDContract.filters.SettleRequested();
  provider.on(settleRequestedFilter, async (log) => {
    console.log("Event SettleRequested emitted");
    // const settleRequestLog = pricelessCFDContract.interface.parseLog(log);

    const curAssetPrice = await getAssetPrice();

    const assetOpeningPrice = await pricelessCFDContract.refAssetOpeningPrice();
    const assetMaxDelta = await pricelessCFDContract.refAssetPriceMaxDelta();
    const ceilPrice = assetOpeningPrice.add(assetMaxDelta);
    const floorPrice = assetOpeningPrice.sub(assetMaxDelta);

    if (!(curAssetPrice.gte(ceilPrice) || curAssetPrice.lte(floorPrice))) {
      const disputeSettleRequestEthCollateral = await pricelessCFDContract.disputeSettleRequestEthCollateral();
      // Dispute request if the current asset price isn't
      // worth settling
      console.log("Event SettleRequested invalid, disputing...");
      const tx = await pricelessCFDContract.disputeSettleRequest({
        value: disputeSettleRequestEthCollateral,
      });
      await tx.wait();
      console.log("Event SettleRequested disputed");
    } else {
      console.log("Event SettleRequested valid");
    }
  });
};

const main = async () => {
    await setupSettleRequestListener();
    console.log("Listening for SettleRequested events");
};

main();
