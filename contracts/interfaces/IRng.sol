// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

interface IRng {
    
    /**
     * @param _quantity The quantity of random numbers to output.
     * @return A random number array of the given length.
     */
    function getRandomNumbers(uint256 _quantity) external returns (uint256[] memory);
}
