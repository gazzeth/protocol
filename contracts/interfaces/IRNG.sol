// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IRNG {
    
    function getRandomNumbers(uint256 _quantity) external returns (uint256[] memory);
}
