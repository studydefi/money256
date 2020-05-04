pragma solidity ^0.5.16;

interface IBPool {
    function BONE() external view returns (uint256);

    function BPOW_PRECISION() external view returns (uint256);

    function EXIT_FEE() external view returns (uint256);

    function INIT_POOL_SUPPLY() external view returns (uint256);

    function MAX_BOUND_TOKENS() external view returns (uint256);

    function MAX_BPOW_BASE() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function MAX_IN_RATIO() external view returns (uint256);

    function MAX_OUT_RATIO() external view returns (uint256);

    function MAX_TOTAL_WEIGHT() external view returns (uint256);

    function MAX_WEIGHT() external view returns (uint256);

    function MIN_BALANCE() external view returns (uint256);

    function MIN_BOUND_TOKENS() external view returns (uint256);

    function MIN_BPOW_BASE() external view returns (uint256);

    function MIN_FEE() external view returns (uint256);

    function MIN_WEIGHT() external view returns (uint256);

    function allowance(address src, address dst)
        external
        view
        returns (uint256);

    function approve(address dst, uint256 amt) external returns (bool);

    function balanceOf(address whom) external view returns (uint256);

    function bind(address token, uint256 balance, uint256 denorm) external;

    function calcInGivenOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountIn);

    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountOut);

    function calcPoolInGivenSingleOut(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 poolAmountIn);

    function calcPoolOutGivenSingleIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 poolAmountOut);

    function calcSingleInGivenPoolOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountIn);

    function calcSingleOutGivenPoolIn(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountOut);

    function calcSpotPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 swapFee
    ) external pure returns (uint256 spotPrice);

    function decimals() external view returns (uint8);

    function decreaseApproval(address dst, uint256 amt) external returns (bool);

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external returns (uint256 poolAmountIn);

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut);

    function finalize() external;

    function getBalance(address token) external view returns (uint256);

    function getColor() external view returns (bytes32);

    function getController() external view returns (address);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function getDenormalizedWeight(address token)
        external
        view
        returns (uint256);

    function getFinalTokens() external view returns (address[] memory tokens);

    function getNormalizedWeight(address token) external view returns (uint256);

    function getNumTokens() external view returns (uint256);

    function getSpotPrice(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 spotPrice);

    function getSwapFee() external view returns (uint256);

    function getTotalDenormalizedWeight() external view returns (uint256);

    function gulp(address token) external;

    function increaseApproval(address dst, uint256 amt) external returns (bool);

    function isBound(address t) external view returns (bool);

    function isFinalized() external view returns (bool);

    function isPublicSwap() external view returns (bool);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);

    function joinswapPoolAmountOut(
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn
    ) external returns (uint256 tokenAmountIn);

    function name() external view returns (string memory);

    function rebind(address token, uint256 balance, uint256 denorm) external;

    function setController(address manager) external;

    function setPublicSwap(bool public_) external;

    function setSwapFee(uint256 swapFee) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function transfer(address dst, uint256 amt) external returns (bool);

    function transferFrom(address src, address dst, uint256 amt)
        external
        returns (bool);

    function unbind(address token) external;
}
