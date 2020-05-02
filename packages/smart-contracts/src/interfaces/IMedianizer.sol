pragma solidity ^0.5.16;

interface IMedianizer {
    function read() external view returns (bytes32);
}
