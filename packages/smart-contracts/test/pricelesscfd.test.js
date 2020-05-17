require('dotenv').config({ path: '../../.env' });
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
  process.env.PK_DEPLOYER,
  provider
);

const disputerWallet = new ethers.Wallet(
  process.env.PK_DISPUTER,
  provider
);

const minterWallet1 = new ethers.Wallet(
  process.env.PK_MINTER_1,
  provider
);

const minterWallet2 = new ethers.Wallet(
  process.env.PK_MINTER_2,
  provider
);

const genericWallet1 = new ethers.Wallet(
  process.env.PK_GENERIC_1,
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

const newERC20Contract = (x) =>
  new ethers.Contract(x, legos.erc20.dai.abi, provider);

const daiContract = newERC20Contract(legos.erc20.dai.address);

let longTokenContract;
let shortTokenContract;

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

  longTokenContract = newERC20Contract(await pricelessCFDContract.longToken());
  shortTokenContract = newERC20Contract(
    await pricelessCFDContract.shortToken()
  );
});

describe("PricessCFD", () => {
  test("mint and redeem", async () => {
    await getDaiFromUniswap(minterWallet1);

    // Contract daiBalance
    const initialDaiBalContract = await daiContract.balanceOf(
      pricelessCFDContract.address
    );

    // We deployed the contract at ref price of 1 DAI
    // with max delta of 0.2
    // Ceil = 1.2, floor = 0.8
    // Long + Short = 2 DAI ALWAYS
    const daiDeposited = ethers.utils.parseEther("100.0");

    // Approve contract to get funds from contract
    await daiContract
      .connect(minterWallet1)
      .approve(pricelessCFDContract.address, daiDeposited);

    // Get amount of tokens
    const preMintLongToken = await longTokenContract.balanceOf(
      minterWallet1.address
    );
    const preMintShortToken = await shortTokenContract.balanceOf(
      minterWallet1.address
    );

    // Mints 1 long and 1 short token
    const reqMintTx = await pricelessCFDContract
      .connect(minterWallet1)
      .mint(daiDeposited);

    await reqMintTx.wait();

    // Check new balances
    const postMintLongToken = await longTokenContract.balanceOf(
      minterWallet1.address
    );
    const postMintShortToken = await shortTokenContract.balanceOf(
      minterWallet1.address
    );

    const tokenMintedLong = postMintLongToken.sub(preMintLongToken);
    const tokenMintedShort = postMintShortToken.sub(preMintShortToken);

    expect(postMintLongToken.gt(preMintLongToken)).toBe(true);
    expect(postMintShortToken.gt(preMintShortToken)).toBe(true);
    expect(tokenMintedLong.eq(tokenMintedShort)).toBe(true);

    // Redeem tokens
    await longTokenContract
      .connect(minterWallet1)
      .approve(pricelessCFDContract.address, tokenMintedLong);
    await shortTokenContract
      .connect(minterWallet1)
      .approve(pricelessCFDContract.address, tokenMintedShort);

    const reqRedeemTx = await pricelessCFDContract
      .connect(minterWallet1)
      .redeem(tokenMintedLong);

    await reqRedeemTx.wait();

    // DAI Balance should be exactly the same prior to minting
    const postRedeemDaiBalContract = await daiContract.balanceOf(
      pricelessCFDContract.address
    );

    expect(initialDaiBalContract.eq(postRedeemDaiBalContract)).toBe(true);
  });

  test("request settlement (no dispute)", async () => {
    // Get me some DAI
    await getDaiFromUniswap(genericWallet1);

    // Contract daiBalance
    const initialDaiBal = await daiContract.balanceOf(genericWallet1.address);

    // Mint some tokens
    // Mints 1 long and 1 short token
    const daiDeposited = ethers.utils.parseEther("150.0");

    await daiContract
      .connect(genericWallet1)
      .approve(pricelessCFDContract.address, daiDeposited);

    const reqMintTx = await pricelessCFDContract
      .connect(genericWallet1)
      .mint(daiDeposited);

    await reqMintTx.wait();

    // Settlement can only happen if the price of the underlying
    // exceeds the bounds
    const openingPrice = await pricelessCFDContract.refAssetOpeningPrice();
    const maxDelta = await pricelessCFDContract.refAssetPriceMaxDelta();
    const ceilPrice = openingPrice.add(maxDelta);

    // Calculate ETH collateral requirements
    const settleRequestEthCollateral = await pricelessCFDContract.settleRequestEthCollateral();

    // Requests for a settlement
    const reqSettleTx = await pricelessCFDContract
      .connect(genericWallet1)
      .requestSettle(ceilPrice, { value: settleRequestEthCollateral });
    await reqSettleTx.wait();

    await sleep(10000);

    // Process settlement
    const processSettleReqTx = await pricelessCFDContract
      .connect(genericWallet1)
      .processSettleRequest();
    await processSettleReqTx.wait();

    // Redeem final
    await longTokenContract
      .connect(genericWallet1)
      .approve(
        pricelessCFDContract.address,
        await longTokenContract.balanceOf(genericWallet1.address)
      );
    await shortTokenContract
      .connect(genericWallet1)
      .approve(
        pricelessCFDContract.address,
        await shortTokenContract.balanceOf(genericWallet1.address)
      );

    await pricelessCFDContract.connect(genericWallet1).redeemFinal();

    // Get daiBalance
    const finalDaiBalance = await daiContract.balanceOf(genericWallet1.address);

    expect(initialDaiBal.eq(finalDaiBalance)).toBe(true);
  });
});
