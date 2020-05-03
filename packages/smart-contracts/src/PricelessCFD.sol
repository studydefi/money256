// Special thanks to
// https://github.com/Daichotomy/UpSideDai/blob/master/contracts/CFD.sol
// for the CFD reference

// https://github.com/UMAprotocol/protocol/blob/master/core/contracts/financial-templates/implementation/Liquidatable.sol
// for a liquidatable reference

pragma solidity ^0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@studydefi/money-legos/uniswap/contracts/IUniswapFactory.sol";
import "@studydefi/money-legos/uniswap/contracts/IUniswapExchange.sol";

import "./interfaces/OracleInterface.sol";
import "./interfaces/IMedianizer.sol";

import "./lib/StableMath.sol";

import "./Token.sol";


contract PricelessCFD {
    /***********************************
        Contract for difference contract to long/short some asset
        Note the assets will be priced in USD, i.e. <x> USD for 1 unit of Asset
        We will also hold a couple of assumptions, for e.g. that 1 DAI = 1 USD
        Therefore, we will be assuming that USD/Asset = DAI/Asset
    ************************************/

    using StableMath for uint256;

    /***********************************
        External Contracts
    ************************************/
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

    IMedianizer usdEthPriceFeed = IMedianizer(
        0x729D19f657BD0614b4985Cf1D82531c67569197B
    );

    OracleInterface oracle;

    /***********************************
        CFD Parameters
    ************************************/
    bytes32 public identifier = "PricelessCFD";

    // Everything is in 18 units of wei
    // i.e. x2 leverage is 2e18
    //      100% fee is 1e18, 0.5% fee is 3e15
    uint256 public curMintId;
    uint256 public leverage;
    uint256 public feeRate;
    uint256 public settlementEpoch;
    uint256 public refAssetOpeningPrice; // Price, we assume it'll be USD/Asset in every case
    uint256 public refAssetPriceMaxDelta; // How much will this contract allow them to deviate from opening price
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

    /***********************************
        Liquidation data structures
    ************************************/
    enum Status {
        Uninitialized,
        PreDispute,
        PendingDispute,
        DisputeSucceeded,
        DisputeFailed
    }

    /***********************************
        Liquidity providers
    ************************************/
    struct MintRequest {
        address minter;
        uint256 mintTime;
        uint256 refAssetPriceAtMint;
        uint256 longInEthDeposited; // Long token in ETH
        uint256 shortInEthDeposited; // Short token in ETH
        uint256 daiDeposited; // How much DAI has been deposited
        bool processed; // Has the mint request been processed
        Status status; // State of the mint request
        address disputer; // Person who is disputing a liquidation
    }

    // Each mint request needs to wait for ~mintRequestDisputablePeriod
    // before users can process it (in seconds)
    // TODO: Change this when not testing
    uint256 public mintRequestDisputablePeriod = 0;

    // Collateral needed to dispute a mint request (0.1 ETH)
    uint256 public disputeMintRequestFee = 1e17;

    // MintId => MintRequest
    mapping(uint256 => MintRequest) public mintRequests;

    event MintRequested(uint256 mintId, address minter);
    event DisputeMintRequested(uint256 mintId, address disputer);
    event MintProcessed(uint256 mintId, address minter);

    struct SettleRequest {
        address settler;
        address disputer;
        uint256 time;
        Status status;
    }

    event SettleRequested(address settler, uint256 time);
    event DisputeSettleRequested(
        address disputer,
        address settler,
        uint256 time
    );

    // TODO: Change this when not testing
    uint256 public settleRequestDisputablePeriod = 10;
    uint256 public settleRequestEthCollateral = 1e17;
    uint256 public disputeSettleRequestFee = 1e17;
    SettleRequest curSettleRequest;

    struct Stake {
        uint256 longLP;
        uint256 shortLP;
        uint256 mintVolumeInDai;
        bool liquidated;
    }

    mapping(address => Stake) public stakes;

    /***********************************
        Constructor
    ************************************/
    constructor(
        uint256 _leverage,
        uint256 _feeRate,
        uint256 _settlementEpoch,
        uint256 _refAssetOpeningPrice,
        uint256 _refAssetPriceMaxDelta,
        uint256 _window,
        address _oracle
    ) public {
        leverage = _leverage;
        feeRate = _feeRate;
        settlementEpoch = _settlementEpoch;

        refAssetOpeningPrice = _refAssetOpeningPrice;
        refAssetPriceMaxDelta = _refAssetPriceMaxDelta;

        window = _window;

        oracle = OracleInterface(_oracle);

        longToken = new Token("Long Token", "LTKN");
        shortToken = new Token("Short Token", "STKN");

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

    /***********************************
        Modifiers
    ************************************/
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

    /***********************************
        Liquidity providers
    ************************************/

    // Submits a mint request
    // Will need to approve a similar amount of DAI w.r.t ETH supplied
    function requestMint(
        uint256 expiration,
        uint256 curRefAssetPrice,
        uint256 daiDeposited
    ) external payable notInSettlementPeriod returns (uint256) {
        // Make sure liquidity provider is valid
        if (expiration > now.add(window)) {
            revert("Expiration time too long");
        }
        if (now > expiration) {
            revert("Minting expired");
        }

        // 1. Calculate ETH equilavent in DAI
        // Using a single wei here means 0 slippage and allows pricing from low liq pool
        // extrapolate to base 1e18 in order to do calcs
        require(
            daiToken.transferFrom(msg.sender, address(this), daiDeposited),
            "Transfer DAI for requestMint failed"
        );

        // 2. Calculate the value of the tokens in ETH
        (
            uint256 longTokenInEth,
            uint256 shortTokenInEth
        ) = getETHCollateralRequirements(daiDeposited, curRefAssetPrice);

        uint256 totalEthCollateral = longTokenInEth.add(shortTokenInEth);
        require(msg.value >= totalEthCollateral, "ETH collateral not met");
        if (msg.value > totalEthCollateral) {
            msg.sender.transfer(msg.value.sub(totalEthCollateral));
        }

        // 3. Create a mint request
        MintRequest memory mintRequest = MintRequest({
            minter: msg.sender,
            mintTime: now,
            refAssetPriceAtMint: curRefAssetPrice,
            longInEthDeposited: longTokenInEth,
            shortInEthDeposited: shortTokenInEth,
            daiDeposited: daiDeposited,
            processed: false,
            status: Status.PreDispute,
            disputer: address(0)
        });

        mintRequests[curMintId] = mintRequest;

        emit MintRequested(curMintId, msg.sender);

        // Bump mint request
        curMintId = curMintId + 1;

        return curMintId - 1;
    }

    function disputeMintRequest(uint256 mintId)
        public
        payable
        notInSettlementPeriod
    {
        MintRequest storage mintRequest = mintRequests[mintId];

        require(msg.value >= disputeMintRequestFee, "Lacking fee to dispute!");

        require(
            mintRequest.processed == false,
            "Mint request has been processed!"
        );
        require(
            mintRequest.status == Status.PreDispute,
            "Mint request is already in dispute!"
        );

        // Refund access fee
        if (msg.value > disputeMintRequestFee) {
            msg.sender.call.value(msg.value.sub(disputeMintRequestFee))("");
        }

        // Set dispute status
        mintRequest.disputer = msg.sender;
        mintRequest.status = Status.PendingDispute;

        // Request price from Oracle
        oracle.requestPrice(identifier, mintRequest.mintTime);

        emit DisputeMintRequested(mintId, msg.sender);
    }

    function processMintRequest(uint256 mintId) public notInSettlementPeriod {
        MintRequest storage mintRequest = mintRequests[mintId];

        // Make sure only mintRequest hasn't been processed yet
        require(
            mintRequest.processed == false,
            "Mint request has been processed!"
        );

        // Make sure only mintRequest is at the very least initialized
        require(
            mintRequest.status != Status.Uninitialized,
            "Mint request has not been initialized!"
        );

        // If the mint request is predisputed, make sure the mint request is "mature" enough
        if (mintRequest.status == Status.PreDispute) {
            require(
                mintRequest.mintTime.add(mintRequestDisputablePeriod) <= now,
                "Mint request still in disputable period!"
            );
        }

        // If the mint request is still pending dispute,
        // Check the oracle price, and update it if necessary
        if (mintRequest.status == Status.PendingDispute) {
            if (oracle.hasPrice(identifier, mintRequest.mintTime)) {
                uint256 oraclePrice = uint256(
                    oracle.getPrice(identifier, mintRequest.mintTime)
                );

                // If oracle price == mint price requested
                // Then its valid, send dispute fees back to minter

                // TODO: Maybe give it some lee-way?
                if (mintRequest.refAssetPriceAtMint == oraclePrice) {
                    mintRequest.status = Status.DisputeFailed;
                    mintRequest.minter.call.value(disputeMintRequestFee)("");
                } else {
                    mintRequest.status = Status.DisputeSucceeded;

                    // Minter loses their funds to disputer
                    // TODO: In future disputer has to put up
                    //       a proportional amount of collateral
                    mintRequest.disputer.call.value(
                        mintRequest.longInEthDeposited.add(
                            mintRequest.shortInEthDeposited
                        )
                    );

                    require(
                        daiToken.transferFrom(
                            address(this),
                            mintRequest.disputer,
                            mintRequest.daiDeposited
                        ),
                        "Transfer DAI for requestMint failed"
                    );
                }
            }
        }

        // If we have reached it so far, it means that its a valid mint request
        if (
            mintRequest.status == Status.PreDispute ||
            mintRequest.status == Status.DisputeFailed
        ) {
            _processMintRequestSuccess(mintId);
        }
    }

    function _processMintRequestSuccess(uint256 mintId) internal {
        MintRequest storage mintRequest = mintRequests[mintId];

        // 1. Mint the long/short tokens for the synthetic asset
        uint256 daiDepositedHalf = mintRequest.daiDeposited.div(2);
        longToken.mint(address(this), daiDepositedHalf);
        shortToken.mint(address(this), daiDepositedHalf);

        // 2. Contribute to Uniswap
        uint256 longLP = uniswapLongTokenExchange.addLiquidity.value(
            mintRequest.longInEthDeposited
        )(1, daiDepositedHalf, now.add(3600));

        uint256 shortLP = uniswapShortTokenExchange.addLiquidity.value(
            mintRequest.shortInEthDeposited
        )(1, daiDepositedHalf, now.add(3600));

        // 3. Save total mint volume in ETH
        totalMintVolumeInEth = totalMintVolumeInEth
            .add(mintRequest.longInEthDeposited)
            .add(mintRequest.shortInEthDeposited);

        // 4. Save to staker's profile
        stakes[mintRequest.minter] = Stake({
            longLP: stakes[mintRequest.minter].longLP.add(longLP),
            shortLP: stakes[mintRequest.minter].shortLP.add(shortLP),
            mintVolumeInDai: stakes[mintRequest.minter].mintVolumeInDai.add(
                mintRequest.daiDeposited
            ),
            liquidated: false
        });

        // 5. Mark mint request as processed and emit event
        mintRequest.processed = true;
        emit MintProcessed(mintId, mintRequest.minter);

        // TODO: Convert DAI into cDAI/aDAI or some interest bearing token
    }

    function requestSettle() public payable notInSettlementPeriod {
        // A request to settle is sent
        require(
            curSettleRequest.status == Status.Uninitialized,
            "There is a pending settle request"
        );
        require(
            msg.value >= settleRequestEthCollateral,
            "Not enough ETH collateral to submit settle request"
        );

        // Transfer back remaining funds
        if (msg.value > settleRequestEthCollateral) {
            msg.sender.call.value(msg.value.sub(settleRequestEthCollateral))(
                ""
            );
        }

        curSettleRequest.settler = msg.sender;
        curSettleRequest.time = now;
        curSettleRequest.status = Status.PreDispute;

        emit SettleRequested(msg.sender, now);
    }

    function disputeSettleRequest() public payable notInSettlementPeriod {
        require(
            curSettleRequest.status == Status.PreDispute,
            "Settle request needs to be in PreDispute!"
        );
        require(
            msg.value >= disputeSettleRequestFee,
            "Missing dispute settle request fee!"
        );

        // Refund access fee
        if (msg.value > disputeSettleRequestFee) {
            msg.sender.call.value(msg.value.sub(disputeSettleRequestFee))("");
        }

        curSettleRequest.status = Status.PendingDispute;
        curSettleRequest.disputer = msg.sender;

        emit DisputeSettleRequested(
            msg.sender,
            curSettleRequest.settler,
            curSettleRequest.time
        );
    }

    function processSettleRequest() public notInSettlementPeriod {
        // Settle request is at the very least initialized
        require(
            curSettleRequest.status != Status.Uninitialized,
            "Settle request has not been initialized!"
        );

        // If the settle request is predisputed, make sure the mint request is "mature" enough
        if (curSettleRequest.status == Status.PreDispute) {
            require(
                curSettleRequest.time.add(settleRequestDisputablePeriod) <= now,
                "Settle request still in disputable period!"
            );
        }

        if (curSettleRequest.status == Status.PendingDispute) {
            if (oracle.hasPrice(identifier, curSettleRequest.time)) {
                uint256 oraclePrice = uint256(
                    oracle.getPrice(identifier, curSettleRequest.time)
                );

                bool priceIsPositive = oraclePrice > refAssetOpeningPrice;

                uint256 delta = priceIsPositive
                    ? oraclePrice.sub(refAssetOpeningPrice)
                    : refAssetOpeningPrice.sub(oraclePrice);

                // Valid settlement, settler gets collateral from disputer
                if (delta > refAssetPriceMaxDelta) {
                    curSettleRequest.status = Status.DisputeFailed;
                    curSettleRequest.settler.call.value(
                        disputeSettleRequestFee
                    )("");
                } else {
                    // Invalid settlement, disputer get collateral from settler
                    curSettleRequest.disputer.call.value(
                        settleRequestEthCollateral
                    )("");

                    // Reinitialize dispute
                    curSettleRequest.status = Status.Uninitialized;
                    curSettleRequest.disputer = address(0);
                    curSettleRequest.settler = address(0);
                    curSettleRequest.time = 0;
                }
            }
        }

        // If we've reached here after all the checks, it means that
        // the settlement is valid
        if (
            curSettleRequest.status == Status.DisputeFailed ||
            curSettleRequest.status == Status.PreDispute
        ) {
            // TODO: Have a reward to settler (probably via DAI interest)

            curSettleRequest.settler.call.value(settleRequestEthCollateral)("");
            inSettlementPeriod = true;
            emit SettleRequested(
                curSettleRequest.settler,
                curSettleRequest.time
            );
        }
    }

    function getETHCollateralRequirements(
        uint256 daiDeposited,
        uint256 curRefAssetPrice
    ) public view returns (uint256, uint256) {
        // Individual deposits
        uint256 individualDeposits = daiDeposited.div(2);

        // Get (leverage) rates for long/short token, according to the
        // supplied reference price
        (uint256 longRate, uint256 shortRate) = getLongShortRates(
            curRefAssetPrice
        );

        uint256 totalLongDaiValue = longRate.mulTruncate(individualDeposits);
        uint256 totalShortDaiValue = shortRate.mulTruncate(individualDeposits);

        // Rate is USD/Asset or DAI/Asset
        // Assume 1 DAI = 1 USD
        // Get current DAI per ETH
        uint256 daiPerEthSimple = uniswapDaiExchange.getEthToTokenInputPrice(
            1e6
        );
        uint256 daiPerEthExact = daiPerEthSimple.mul(1e12);

        // Get ETH per Asset
        return (
            totalLongDaiValue.divPrecisely(daiPerEthExact),
            totalShortDaiValue.divPrecisely(daiPerEthExact)
        );
    }

    // What are the current exchange rates for long/short token rates
    function getLongShortRates(uint256 curRefAssetPrice)
        public
        view
        returns (uint256, uint256)
    {
        bool priceIsPositive = curRefAssetPrice > refAssetOpeningPrice;

        uint256 delta = priceIsPositive
            ? curRefAssetPrice.sub(refAssetOpeningPrice)
            : refAssetOpeningPrice.sub(curRefAssetPrice);

        if (delta > refAssetPriceMaxDelta) {
            // Users will have chance to dispute it
            revert(
                "Asset price has exceeded bounds, please call requestSettle instead"
            );
        }

        uint256 deltaWithLeverage = delta.mulTruncate(leverage);

        uint256 winRate = refAssetOpeningPrice.add(deltaWithLeverage);
        uint256 loseRate = refAssetOpeningPrice.sub(deltaWithLeverage);

        if (priceIsPositive) {
            return (winRate, loseRate);
        } else {
            return (loseRate, winRate);
        }
    }
}
