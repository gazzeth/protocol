// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/drafts/IERC20Permit.sol";

interface IErc20PermitMintable is IERC20, IERC20Permit {
    
    function mint(address _toAccount, uint256 _amount) external;

    function burn(address _fromAccount, uint256 _amount) external;
}
