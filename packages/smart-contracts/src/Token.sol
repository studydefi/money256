pragma solidity ^0.5.16;

import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract Token is ERC20Detailed, ERC20Mintable, ERC20Burnable {
    constructor(string memory name, string memory symbol)
        public
        ERC20Detailed(name, symbol, 18)
    {
    }
}