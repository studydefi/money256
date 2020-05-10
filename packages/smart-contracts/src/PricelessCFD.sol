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
    uint256 public curMintId;
    uint256 public leverage;
    uint256 public feeRate;
    uint256 public settlementEpoch;
    uint256 public refAssetOpeningPrice; // Price, we assume it'll be USD/Asset in every case
    uint256 public refAssetPriceMaxDelta; // How much will this contract allow them to deviate from opening price
    uint256 public totalMintVolumeInDai;

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
    event Minted(uint256 mintAmount);

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
        uint256 longTokens;
        uint256 shortTokens;
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

        // Long Token
        bPool.bind(address(longToken), minBal, 125e17);

        // Short token
        bPool.bind(address(shortToken), minBal, 125e17);

        bPool.setPublicSwap(true);
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
}
