// Special thanks to
// https://github.com/Daichotomy/UpSideDai/blob/master/contracts/CFD.sol
// for the CFD reference

// https://github.com/UMAprotocol/protocol/blob/master/core/contracts/financial-templates/implementation/Liquidatable.sol
// for a liquidatable reference

pragma solidity ^0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@studydefi/money-legos/maker/contracts/IMedianizer.sol";
import "@studydefi/money-legos/uniswap/contracts/IUniswapFactory.sol";
import "@studydefi/money-legos/uniswap/contracts/IUniswapExchange.sol";

import "./interfaces/IOracle.sol";

import "./lib/StableMath.sol";

import "./Token.sol";


contract PricelessCFD {
    /*
        Contract for difference contract to long/short the USD/EUR
    */

    using StableMath for uint256;

    /*
        External Contracts
    */
    Token public longToken;
    Token public shortToken;

    IUniswapFactory uniswapFactory = IUniswapFactory(
        0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95
    );
    IUniswapExchange uniswapLongTokenExchange;
    IUniswapExchange uniswapShortTokenExchange;

    IERC20 public daiToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IUniswapExchange uniswapDaiExchange = IUniswapExchange(
        uniswapFactory.getExchange(address(daiToken))
    );

    /*
        CFD Parameters
    */
    uint256 public curMintId;
    uint256 public leverage;
    uint256 public feeRate;
    uint256 public settlementEpoch;
    uint256 public refAssetOpeningPrice; // Price = Unit in this case
    uint256 public refAssetMaxUnitDelta; // How much will this contract allow them to deviate from opening price
    uint256 public refAssetUnitPerTick; // What size is considered a "tick"
    uint256 public refAssetEthPerTick; // How much ETH per tick
    uint256 public totalMintVolumeInEth;

    // Because we're using a priceless synthetic
    // we don't know the price of the underlying asset
    // when the user mints it. As such, we're
    // relying on the user to submit honest data
    // which can be disputed. Should the user be disputed
    // then they lose _all_ their deposited collateral.
    // The window is max delta between now and when
    // the option to `mint` expires
    // Should be 10 mins by default
    uint256 public window;

    bool public inSettlementPeriod = false;

    /*
        Liquidity providers
    */
    struct CFDMintData {
        address minter;
        uint256 mintTime;
        uint256 refAssetPriceAtMint;
        uint256 longEthUnits;
        uint256 shortEthUnits;
        uint256 daiDeposited;
    }
    mapping(uint256 => CFDMintData) public mints;

    /*
        Liquidation data structures
    */
    enum Status {
        Uninitialized,
        PreDispute,
        PendingDispute,
        DisputeSucceeded,
        DisputeFailed
    }

    struct LiquidationData {
        uint256 mintId;
        address liquidator;
        Status state;
        uint256 liquidationTimeInitiated;
    }

    /*
        Constructor
    */
    constructor(
        uint256 _leverage,
        uint256 _feeRate,
        uint256 _settlementEpoch,
        uint256 _refAssetOpeningPrice,
        uint256 _refAssetMaxUnitDelta,
        uint256 _refAssetUnitPerTick,
        uint256 _refAssetEthPerTick,
        uint256 _window
    ) public {
        leverage = _leverage;
        feeRate = _feeRate;
        settlementEpoch = _settlementEpoch;

        refAssetOpeningPrice = _refAssetOpeningPrice;
        refAssetMaxUnitDelta = _refAssetMaxUnitDelta;
        refAssetUnitPerTick = _refAssetUnitPerTick;
        refAssetEthPerTick = _refAssetEthPerTick;

        window = _window;

        longToken = new Token("Long USD/EUR", "L_USD_EUR");
        shortToken = new Token("Short USD/EUR", "S_USD_EUR");

        // TODO: Switch to balancer?
        uniswapFactory = IUniswapFactory(
            0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95
        );
        uniswapLongTokenExchange = IUniswapExchange(
            uniswapFactory.createExchange(address(longToken))
        );
        uniswapShortTokenExchange = IUniswapExchange(
            uniswapFactory.createExchange(address(shortToken))
        );

        require(
            longToken.approve(address(uniswapLongTokenExchange), uint256(-1)),
            "Long token approval failed"
        );

        require(
            shortToken.approve(address(uniswapShortTokenExchange), uint256(-1)),
            "Short token approval failed"
        );
    }

    /*
        Modifiers
    */
    modifier notInSettlementPeriod() {
        if (now > settlementEpoch) {
            inSettlementPeriod = true;
        }
        require(!inSettlementPeriod, "Must not be in settlement period");
        _;
    }

    modifier onlyInSettlementPeriod() {
        require(inSettlementPeriod, "Must be in settlement period");
        _;
    }

    /*
        Liquidity providers
    */
    function mint(uint256 expiration, uint256 curRefAssetPrice)
        external
        payable
        notInSettlementPeriod
    {
        // Make sure liquidity provider is valid
        if (expiration > now.add(window)) {
            revert("Expiration too large");
        }
        if (now > expiration) {
            revert("Minting expired");
        }

        // 1. Calculate the value of the tokens in ETH
        (
            uint256 longTokenInEth,
            uint256 shortTokenInEth
        ) = getETHCollateralRequirements(curRefAssetPrice);

        uint256 totalEthCollateral = longTokenInEth.add(shortTokenInEth);
        require(msg.value >= totalEthCollateral, "ETH collateral not met");
        if (msg.value > totalEthCollateral) {
            msg.sender.transfer(msg.value.sub(totalEthCollateral));
        }

        // 2. Calculate ETH equilavent in DAI
        uint256 daiCollateralRequirement = uniswapDaiExchange
            .getEthToTokenInputPrice(totalEthCollateral);
        require(
            daiToken.transferFrom(
                msg.sender,
                address(this),
                daiCollateralRequirement
            ),
            "Transfer DAI for mint failed"
        );

        // 3. Mint the long/short tokens for the synthetic asset
        uint256 daiCollateralHalf = daiCollateralRequirement.div(2);
        longToken.mint(address(this), daiCollateralHalf);
        shortToken.mint(address(this), daiCollateralHalf);

        // 4. Contribute to Uniswap
        uint256 longLP = uniswapLongTokenExchange.addLiquidity.value(
            longTokenInEth
        )(1, daiCollateralHalf, now.add(3600));

        uint256 shortLP = uniswapShortTokenExchange.addLiquidity.value(
            shortTokenInEth
        )(1, daiCollateralHalf, now.add(3600));

        // 5. Short the LP and log mint volume
        totalMintVolumeInEth = totalMintVolumeInEth + totalEthCollateral;

        // TODO: Add mintId and dispute time

        curMintId = curMintId + 1;
    }

    function getETHCollateralRequirements(uint256 curRefAssetPrice)
        public
        returns (uint256, uint256)
    {
        (uint256 longRate, uint256 shortRate) = getLongShortRates(
            curRefAssetPrice
        );

        uint256 totalLongInTicks = longRate.divPrecisely(refAssetUnitPerTick);
        uint256 totalShortInTicks = shortRate.divPrecisely(refAssetUnitPerTick);

        // Get ETH amount needed for
        return (
            totalLongInTicks.mulTruncate(refAssetEthPerTick),
            totalShortInTicks.mulTruncate(refAssetEthPerTick)
        );
    }

    // What are the current exchange rates for long/short token rates
    function getLongShortRates(uint256 curRefAssetPrice)
        public
        returns (uint256, uint256)
    {
        bool priceIsPositive = curRefAssetPrice > refAssetOpeningPrice;

        uint256 delta = priceIsPositive
            ? curRefAssetPrice.sub(refAssetOpeningPrice)
            : refAssetOpeningPrice.sub(curRefAssetPrice);

        uint256 deltaWithLeverage = delta.mulTruncate(leverage);

        if (deltaWithLeverage > refAssetMaxUnitDelta) {
            // TODO: Contract will be going to settlement mode (?)
            // Users will have chance to dispute it
            revert("TODO: Not implemented");
        }

        uint256 winRate = refAssetOpeningPrice.add(deltaWithLeverage);
        uint256 loseRate = refAssetOpeningPrice.sub(deltaWithLeverage);

        if (priceIsPositive) {
            return (winRate, loseRate);
        } else {
            return (loseRate, winRate);
        }
    }
}
