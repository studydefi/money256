// Special thanks to
// https://github.com/Daichotomy/UpSideDai/blob/master/contracts/CFD.sol
// for the CFD reference

// https://github.com/UMAprotocol/protocol/blob/master/core/contracts/financial-templates/implementation/Liquidatable.sol
// for a liquidatable reference

pragma solidity ^0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/OracleInterface.sol";
import "./interfaces/IMedianizer.sol";
import "./interfaces/IBFactory.sol";
import "./interfaces/IBPool.sol";

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

    IBFactory public bFactory = IBFactory(
        0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd
    );
    IBPool public bPool;
    IERC20 public daiToken = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    OracleInterface public oracle;

    /***********************************
        CFD Parameters
    ************************************/
    bytes32 public identifier = "PricelessCFD";

    // Everything is in 18 units of wei
    // i.e. x2 leverage is 2e18
    //      100% fee is 1e18, 0.5% fee is 3e15
    uint256 public leverage;
    uint256 public settlementEpoch;
    uint256 public refAssetOpeningPrice; // Price, we assume it'll be USD/Asset in every case
    uint256 public refAssetPriceMaxDelta; // How much will this contract allow them to deviate from opening price

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
    event Minted(uint256 mintAmount);

    struct SettleRequest {
        address settler;
        address disputer;
        uint256 time;
        uint256 settlementPrice;
        Status status;
    }

    event SettleRequested(
        address settler,
        uint256 time,
        uint256 settlementPrice
    );

    event DisputeSettleRequested(
        address disputer,
        address settler,
        uint256 time
    );

    // TODO: Change this to like 3 hours when not testing
    uint256 public settleRequestDisputablePeriod = 0;
    uint256 public settleRequestEthCollateral = 1e17;
    uint256 public disputeSettleRequestEthCollateral = 1e17;
    SettleRequest curSettleRequest;

    /***********************************
        Constructor
    ************************************/
    constructor(
        uint256 _leverage,
        uint256 _settlementEpoch,
        uint256 _refAssetOpeningPrice,
        uint256 _refAssetPriceMaxDelta,
        address _oracle
    ) public {
        leverage = _leverage;
        settlementEpoch = _settlementEpoch;

        refAssetOpeningPrice = _refAssetOpeningPrice;
        refAssetPriceMaxDelta = _refAssetPriceMaxDelta;

        oracle = OracleInterface(_oracle);

        longToken = new Token("Long Token", "LTKN");
        shortToken = new Token("Short Token", "STKN");
    }

    function initPool() external {
        if (address(bPool) != address(0)) {
            return;
        }

        // Create new pool
        bPool = IBPool(bFactory.newBPool());

        // Approve tokens
        require(
            daiToken.approve(address(bPool), uint256(-1)),
            "Long token approval failed"
        );

        require(
            longToken.approve(address(bPool), uint256(-1)),
            "Long token approval failed"
        );

        require(
            shortToken.approve(address(bPool), uint256(-1)),
            "Short token approval failed"
        );

        uint256 minBal = bPool.MIN_BALANCE();

        longToken.mint(address(this), minBal);
        shortToken.mint(address(this), minBal);

        // Initialize and bind tokens to pool
        bPool.bind(address(daiToken), minBal.mul(2), 25e18);

        // Long Token (50%)
        bPool.bind(address(longToken), minBal, 125e17);

        // Short token (50%)
        bPool.bind(address(shortToken), minBal, 125e17);

        bPool.finalize();
    }

    /***********************************
        Modifiers
    ************************************/
    modifier notInSettlementPeriod() {
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

    // Mints a token
    function mint(uint256 daiDeposited)
        external
        notInSettlementPeriod
        returns (uint256)
    {
        // 1. Get underlying backing DAI
        require(
            daiToken.transferFrom(msg.sender, address(this), daiDeposited),
            "Transfer DAI for requestMint failed"
        );

        // 2. Calculate number of tokens to mint Note:
        // 1 * (Long + Short) = (refAssetOpeningPrice - refAssetPriceMaxDelta) + (refAssetOpeningPrice + refAssetPriceMaxDelta)
        // Therefore, number of minted tokens = daiDeposited / ((refAssetOpeningPrice - refAssetPriceMaxDelta) + (refAssetOpeningPrice + refAssetPriceMaxDelta))
        uint256 floorPrice = refAssetOpeningPrice.sub(refAssetPriceMaxDelta);
        uint256 ceilPrice = refAssetOpeningPrice.add(refAssetPriceMaxDelta);

        uint256 tokensToMint = daiDeposited.divPrecisely(
            floorPrice.add(ceilPrice)
        );

        // 3. Mint tokens to user
        longToken.mint(address(msg.sender), tokensToMint);
        shortToken.mint(address(msg.sender), tokensToMint);

        emit Minted(tokensToMint);
    }

    // Redeems tokens
    function redeem(uint256 redeemAmount) public notInSettlementPeriod {
        // Burn long and short token
        longToken.burnFrom(msg.sender, redeemAmount);
        shortToken.burnFrom(msg.sender, redeemAmount);

        // Calculate Payout $ to user
        uint256 floorPrice = refAssetOpeningPrice.sub(refAssetPriceMaxDelta);
        uint256 ceilPrice = refAssetOpeningPrice.add(refAssetPriceMaxDelta);

        uint256 daiToRefund = redeemAmount.mulTruncate(
            floorPrice.add(ceilPrice)
        );

        // $$ to User
        require(daiToken.transfer(msg.sender, daiToRefund), "Redeem failed");
    }

    // Redeems remaining tokens
    function redeemFinal() public onlyInSettlementPeriod {
        uint256 longTokenAmount = longToken.balanceOf(msg.sender);
        uint256 shortTokenAmount = shortToken.balanceOf(msg.sender);

        // Burn tokens
        longToken.burnFrom(msg.sender, longTokenAmount);
        shortToken.burnFrom(msg.sender, shortTokenAmount);

        // Calculate how much DAI to refund to user
        uint256 deltaLeveraged;
        uint256 longTokenRate;
        uint256 shortTokenRate;

        // If the token has appreciated in value, long token is worth more
        if (curSettleRequest.settlementPrice > refAssetOpeningPrice) {
            deltaLeveraged = curSettleRequest
                .settlementPrice
                .sub(refAssetOpeningPrice)
                .mulTruncate(leverage);

            longTokenRate = refAssetOpeningPrice.add(deltaLeveraged);
            shortTokenRate = refAssetOpeningPrice.sub(deltaLeveraged);
        } else {
            // Else short token has appreciated in value
            deltaLeveraged = refAssetOpeningPrice
                .sub(curSettleRequest.settlementPrice)
                .mulTruncate(leverage);

            longTokenRate = refAssetOpeningPrice.sub(deltaLeveraged);
            shortTokenRate = refAssetOpeningPrice.add(deltaLeveraged);
        }

        // Convert to DAI
        uint256 longDai = longTokenRate.mulTruncate(longTokenAmount);
        uint256 shortDai = shortTokenRate.mulTruncate(shortTokenAmount);
        uint256 totalDaiPayout = longDai.add(shortDai);

        daiToken.transfer(msg.sender, totalDaiPayout);
    }

    function requestSettle(uint256 settlementPrice)
        public
        payable
        notInSettlementPeriod
    {
        // A request to settle is sent
        uint256 floorPrice = refAssetOpeningPrice.sub(refAssetPriceMaxDelta);
        uint256 ceilPrice = refAssetOpeningPrice.add(refAssetPriceMaxDelta);

        // If contract hasn't expired, and a settlement request is requested
        // then it needs to exceed the bounds
        if (now <= settlementEpoch) {
            require(
                settlementPrice == floorPrice || settlementPrice == ceilPrice,
                "Not valid settlement price"
            );
        }

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
        curSettleRequest.settlementPrice = settlementPrice;

        emit SettleRequested(msg.sender, now, settlementPrice);
    }

    function disputeSettleRequest() public payable notInSettlementPeriod {
        require(
            curSettleRequest.status == Status.PreDispute,
            "Settle request needs to be in PreDispute!"
        );
        require(
            msg.value >= disputeSettleRequestEthCollateral,
            "Missing dispute settle request fee!"
        );

        // Refund access fee
        if (msg.value > disputeSettleRequestEthCollateral) {
            msg.sender.call.value(
                msg.value.sub(disputeSettleRequestEthCollateral)
            )("");
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
                        disputeSettleRequestEthCollateral
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
            curSettleRequest.settler.call.value(settleRequestEthCollateral)("");
            inSettlementPeriod = true;
            emit SettleRequested(
                curSettleRequest.settler,
                curSettleRequest.time,
                curSettleRequest.settlementPrice
            );
        }
    }
}
