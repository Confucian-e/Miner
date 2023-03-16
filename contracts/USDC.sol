// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract USDC is ERC20, Ownable {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1e25);
    }

    function mint(uint amount) public onlyOwner {
        _mint(msg.sender, amount * 1e18);
    }
}