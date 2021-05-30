// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDai is IERC20 {
    
    function permit(
        address _holder, address _spender, uint256 _nonce, uint256 _expiry, bool _allowed, uint8 _v, bytes32 _r, bytes32 _s
    ) external;
}
