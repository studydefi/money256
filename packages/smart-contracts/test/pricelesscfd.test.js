const { ethers } = require("ethers");
const { BigNumber } = require("ethers/utils/bignumber");

const { legos } = require("@studydefi/money-legos");

const pricelessCFDDef = require("../build/PricelessCFD.json");

const zeroBN = new BigNumber(0);

const sleep = (ms) => {
  return new Promise((resolve) => setTimeout(resolve, ms));
};

const provider = new ethers.providers.JsonRpcProvider(
  process.env.PROVIDER_URL || "http://localhost:8545"
);

const wallet = new ethers.Wallet(
  "0xb0057716d5917badaf911b193b12b910811c1497b5bada8d7711f758981c3773", // Default private key for ganache-cli -d
  provider
);

const pricelessCFDContract = new ethers.Contract(
  pricelessCFDDef.networks["1"].address,
  pricelessCFDDef.abi,
  wallet
);

const daiContract = new ethers.Contract(
  legos.erc20.dai.address,
  legos.erc20.dai.abi,
  wallet
);

const getCurEpoch = () => parseInt(Date.now() / 1000);

beforeAll(async () => {
  // Get some DAI from Uniswap
  const uniswapFactory = new ethers.Contract(
    legos.uniswap.factory.address,
    legos.uniswap.factory.abi,
    wallet
  );

  const uniswapDaiAddress = await uniswapFactory.getExchange(
    legos.erc20.dai.address
  );

  const uniswapDaiExchange = new ethers.Contract(
    uniswapDaiAddress,
    legos.uniswap.exchange.abi,
    wallet
  );

  const daiPerEth = await uniswapDaiExchange.getEthToTokenInputPrice(
    ethers.utils.parseUnits("1", 6)
  );

  const futureEpoch = getCurEpoch() + 3600;

  const tx = await uniswapDaiExchange.ethToTokenSwapInput(1, futureEpoch, {
    gasLimit: 1500000,
    value: ethers.utils.parseEther("5"),
  });

  await tx.wait();
});

describe("PricessCFD", () => {
  test("requestMint and processMintId", async () => {
    // The asset's price is initialized at 1 DAI,
    // with leverage of 5,
    // window of 600 seconds

    // curRefAssetPrice is at 1.01 DAI

    // As such, buying a longToken will be 1.05 DAI
    //          buying a shortToken will be 0.95 DAI

    // We want to deposit in 100 DAI and ETH equilavent
    // (Note the excess ETH will be redunded)
    const daiDeposited = ethers.utils.parseEther("100.0");
    const curRefAssetPrice = ethers.utils.parseEther("1.01");
    const expiration = getCurEpoch() + 120; // 2 mins in the future

    // Get current ETH collateral requirements
    await pricelessCFDContract.getETHCollateralRequirements(
      daiDeposited,
      curRefAssetPrice
    );

    // Approve contract to get funds from contract
    await daiContract.approve(pricelessCFDContract.address, daiDeposited);

    // Request Mint Tx
    const reqMintTx = await pricelessCFDContract.requestMint(
      expiration,
      curRefAssetPrice,
      daiDeposited,
      {
        value: ethers.utils.parseEther("1.0"),
      }
    );

    const reqMintTxRecp = await reqMintTx.wait();
    const reqMintEvent = reqMintTxRecp.events[1];
    const mintId = reqMintEvent.args.mintId;

    // Process mint request
    const tx = await pricelessCFDContract.processMintRequest(mintId);
    await tx.wait();

    // Make sure we have stakes after minting
    const stake = await pricelessCFDContract.stakes(wallet.address);

    expect(stake.longLP.gt(zeroBN)).toBe(true);
    expect(stake.shortLP.gt(zeroBN)).toBe(true);
    expect(stake.mintVolumeInDai.gt(zeroBN)).toBe(true);
  });
});
