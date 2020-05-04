const { ethers } = require("ethers");
const { BigNumber } = require("ethers/utils/bignumber");

const { legos } = require("@studydefi/money-legos");

const identifierWhitelistDef = require("../build/IdentifierWhitelist.json");
const finderDef = require("../build/Finder.json");
const mockOracleDef = require("../build/MockOracle.json");
const pricelessCFDDef = require("../build/PricelessCFD.json");

const zeroBN = new BigNumber(0);

const sleep = (ms) => {
  return new Promise((resolve) => setTimeout(resolve, ms));
};

const provider = new ethers.providers.JsonRpcProvider(
  process.env.PROVIDER_URL || "http://localhost:8545"
);

const deployerWallet = new ethers.Wallet(
  "0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d",
  provider
);

const disputerWallet = new ethers.Wallet(
  "0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1",
  provider
);

const minterWallet1 = new ethers.Wallet(
  "0x646f1ce2fdad0e6deeeb5c7e8e5543bdde65e86029e2fd9fc169899c440a7913",
  provider
);

const minterWallet2 = new ethers.Wallet(
  "0xb0057716d5917badaf911b193b12b910811c1497b5bada8d7711f758981c3773",
  provider
);

const minterWallet3 = new ethers.Wallet(
  "0x829e924fdf021ba3dbbc4225edfece9aca04b929d6e75613329ca6f1d31c0bb4",
  provider
);

const finderContract = new ethers.Contract(
  finderDef.networks["1"].address,
  finderDef.abi,
  provider
);

const pricelessCFDContract = new ethers.Contract(
  pricelessCFDDef.networks["1"].address,
  pricelessCFDDef.abi,
  provider
);

const mockOracleContract = new ethers.Contract(
  mockOracleDef.networks["1"].address,
  mockOracleDef.abi,
  provider
);

const identifierWhitelistContract = new ethers.Contract(
  identifierWhitelistDef.networks["1"].address,
  identifierWhitelistDef.abi,
  provider
);

const daiContract = new ethers.Contract(
  legos.erc20.dai.address,
  legos.erc20.dai.abi,
  provider
);

const getCurEpoch = () => parseInt(Date.now() / 1000);

const getDaiFromUniswap = async (wallet) => {
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

  const futureEpoch = getCurEpoch() + 3600;

  const tx = await uniswapDaiExchange.ethToTokenSwapInput(1, futureEpoch, {
    gasLimit: 1500000, 
    value: ethers.utils.parseEther("5"),
  });

  await tx.wait();
};

beforeAll(async () => {
  // Get DAI
  await getDaiFromUniswap(deployerWallet);
  await daiContract
    .connect(deployerWallet)
    .transfer(pricelessCFDContract.address, "2000000");

  // Initialize Pool (need 2000000 WEI DAI)
  await pricelessCFDContract
    .connect(deployerWallet)
    .initPool({ gasLimit: 7000000 });

  // Need to initialize pool first
  const identifier = await pricelessCFDContract.identifier();

  await identifierWhitelistContract
    .connect(deployerWallet)
    .addSupportedIdentifier(identifier);

  await finderContract
    .connect(deployerWallet)
    .changeImplementationAddress(
      ethers.utils.formatBytes32String("IdentifierWhitelist"),
      identifierWhitelistContract.address
    );

  await finderContract
    .connect(deployerWallet)
    .changeImplementationAddress(
      ethers.utils.formatBytes32String("Oracle"),
      mockOracleContract.address
    );
});

describe("PricessCFD", () => {
  test("requestMint and processMintId (minterWallet1)", async () => {
    // The asset's price is initialized at 1 DAI,
    // with leverage of 5,
    // window of 600 seconds

    // curRefAssetPrice is at 1.01 DAI
    await getDaiFromUniswap(minterWallet1);

    // As such, buying a longToken will be 1.05 DAI
    //          buying a shortToken will be 0.95 DAI

    // We want to deposit in 100 DAI and ETH equilavent
    // (Note the excess ETH will be redunded)
    const daiDeposited = ethers.utils.parseEther("100.0");
    const curRefAssetPrice = ethers.utils.parseEther("1.01");
    const expiration = getCurEpoch() + 120; // 2 mins in the future

    // Approve contract to get funds from contract
    await daiContract
      .connect(minterWallet1)
      .approve(pricelessCFDContract.address, daiDeposited);

    // Request Mint Tx
    const reqMintTx = await pricelessCFDContract
      .connect(minterWallet1)
      .requestMint(expiration, curRefAssetPrice, daiDeposited, {
        value: ethers.utils.parseEther("1.0"),
      });

    const reqMintTxRecp = await reqMintTx.wait();
    const reqMintEvent = reqMintTxRecp.events[1];
    const mintId = reqMintEvent.args.mintId;

    // Stakes before
    const stakeBefore = await pricelessCFDContract.stakes(
      minterWallet1.address
    );

    // Process mint request
    const tx = await pricelessCFDContract
      .connect(minterWallet1)
      .processMintRequest(mintId);
    await tx.wait();

    // Make sure our stakes increased after minting
    const stakeAfter = await pricelessCFDContract.stakes(minterWallet1.address);

    console.log(stakeAfter)

    expect(stakeAfter.longTokens.gt(stakeBefore.longTokens)).toBe(true);
    expect(stakeAfter.shortTokens.gt(stakeBefore.shortTokens)).toBe(true);
  });

  test("requestMint, dispute(fail) and processMintId (minterWallet2)", async () => {
    // The asset's price is initialized at 1 DAI,
    // with leverage of 5,
    // window of 600 seconds

    // curRefAssetPrice is at 1.01 DAI
    await getDaiFromUniswap(minterWallet2);

    // As such, buying a longToken will be 1.05 DAI
    //          buying a shortToken will be 0.95 DAI

    // We want to deposit in 100 DAI and ETH equilavent
    // (Note the excess ETH will be redunded)
    const daiDeposited = ethers.utils.parseEther("100.0");
    const curRefAssetPrice = ethers.utils.parseEther("1.01");
    const expiration = getCurEpoch() + 120; // 2 mins in the future

    // Approve contract to get funds from contract
    await daiContract
      .connect(minterWallet2)
      .approve(pricelessCFDContract.address, daiDeposited);

    // Request Mint Tx
    const reqMintTx = await pricelessCFDContract
      .connect(minterWallet2)
      .requestMint(expiration, curRefAssetPrice, daiDeposited, {
        value: ethers.utils.parseEther("1.0"),
        gasLimit: 6000000,
      });

    const reqMintTxRecp = await reqMintTx.wait();
    const reqMintEvent = reqMintTxRecp.events[1];
    const mintId = reqMintEvent.args.mintId;
    const mintRequest = await pricelessCFDContract.mintRequests(mintId);

    // Dispute mint request
    const disputeMintRequestFee = await pricelessCFDContract.disputeMintRequestFee();
    await pricelessCFDContract
      .connect(disputerWallet)
      .disputeMintRequest(mintId, {
        value: disputeMintRequestFee,
        gasLimit: 6000000,
      });

    // Oracle set price to be valid with mintRequester
    const identifier = await pricelessCFDContract.identifier();
    await mockOracleContract
      .connect(deployerWallet)
      .pushPrice(identifier, mintRequest.mintTime, curRefAssetPrice);

    // Stakes before
    const stakeBefore = await pricelessCFDContract.stakes(
      minterWallet2.address
    );

    // Process mint request
    const tx = await pricelessCFDContract
      .connect(minterWallet2)
      .processMintRequest(mintId, { gasLimit: 6000000 });
    await tx.wait();

    // Make sure our stakes increased after minting
    const stakeAfter = await pricelessCFDContract.stakes(minterWallet2.address);

    expect(stakeAfter.longTokens.gt(stakeBefore.longTokens)).toBe(true);
    expect(stakeAfter.shortTokens.gt(stakeBefore.shortTokens)).toBe(true);
  });

  test("requestMint, dispute(success) and processMintId (minterWallet3)", async () => {
    // The asset's price is initialized at 1 DAI,
    // with leverage of 5,
    // window of 600 seconds

    // curRefAssetPrice is at 1.01 DAI
    await getDaiFromUniswap(minterWallet3);

    // As such, buying a longToken will be 1.05 DAI
    //          buying a shortToken will be 0.95 DAI

    // We want to deposit in 100 DAI and ETH equilavent
    // (Note the excess ETH will be redunded)
    const daiDeposited = ethers.utils.parseEther("100.0");
    const curInvalidRefAssetPrice = ethers.utils.parseEther("1.01");
    const curValidRefAssetPrice = ethers.utils.parseEther("1.03");
    const expiration = getCurEpoch() + 120; // 2 mins in the future

    // Approve contract to get funds from contract
    await daiContract
      .connect(minterWallet3)
      .approve(pricelessCFDContract.address, daiDeposited);

    // Request Mint Tx
    const reqMintTx = await pricelessCFDContract
      .connect(minterWallet3)
      .requestMint(expiration, curInvalidRefAssetPrice, daiDeposited, {
        value: ethers.utils.parseEther("1.0"),
        gasLimit: 6000000,
      });

    const reqMintTxRecp = await reqMintTx.wait();
    const reqMintEvent = reqMintTxRecp.events[1];
    const mintId = reqMintEvent.args.mintId;
    const mintRequest = await pricelessCFDContract.mintRequests(mintId);

    // Dispute mint request
    const disputeMintRequestFee = await pricelessCFDContract.disputeMintRequestFee();
    await pricelessCFDContract
      .connect(disputerWallet)
      .disputeMintRequest(mintId, {
        value: disputeMintRequestFee,
        gasLimit: 6000000,
      });

    // Oracle set price to be valid with mintRequester
    const identifier = await pricelessCFDContract.identifier();
    await mockOracleContract
      .connect(deployerWallet)
      .pushPrice(identifier, mintRequest.mintTime, curValidRefAssetPrice);

    // Stakes before
    const stakeBefore = await pricelessCFDContract.stakes(
      minterWallet3.address
    );

    // Process mint request
    const tx = await pricelessCFDContract
      .connect(minterWallet3)
      .processMintRequest(mintId, { gasLimit: 6000000 });
    await tx.wait();

    // Make sure our stakes increased after minting
    const stakeAfter = await pricelessCFDContract.stakes(minterWallet3.address);

    expect(stakeAfter.longTokens.eq(stakeBefore.longTokens)).toBe(true);
    expect(stakeAfter.shortTokens.eq(stakeBefore.shortTokens)).toBe(true);
  });
});
