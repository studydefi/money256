pragma solidity ^0.5.16;


contract IBFactory {
    event LOG_NEW_POOL(address indexed caller, address indexed pool);

    event LOG_BLABS(address indexed caller, address indexed blabs);

    function isBPool(address b) external view returns (bool);

    function newBPool() external returns (address);

    function getBLabs() external view returns (address);
}
