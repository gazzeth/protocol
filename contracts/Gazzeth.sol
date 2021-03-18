// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Gazzeth is ERC20 {

    uint8 constant CLAIM_AMOUNT = 10;

    mapping (address => bool) hasAlreadyClaimed;

    constructor() ERC20("Gazzeth", "GZT") {
        _setupDecimals(18);
    }

   /**
     * Mints claimAmount tokens and assign it to the caller. This can be done only once by caller.
     * This function will be removed later when a better mint mechanism is implemented.
     */
    function claim() external {
        require(!hasAlreadyClaimed[msg.sender], "You can only claim for Gazzeths once and you have already done it.");
        hasAlreadyClaimed[msg.sender] = true;
        _mint(msg.sender, CLAIM_AMOUNT);
    }
}
