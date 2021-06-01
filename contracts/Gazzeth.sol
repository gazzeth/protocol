// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";
import "./interfaces/IErc20PermitMintable.sol";

contract Gazzeth is ERC20, ERC20Permit, IErc20PermitMintable {

    using SafeMath for uint256;

    string public constant NAME = "Gazzeth";
    string public constant SYMBOL = "GZT";

    address public owner;
    address public protocolContract;
    bool public protocolContractAddressSet;

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        owner = _msgSender();
    }

    function setProtocolContractAddress(address _protocolContract) external {
        require(_msgSender() == owner, "Only owner can call this function");
        require(!protocolContractAddressSet, "Protocol contract address already set");
        protocolContract = _protocolContract;
        protocolContractAddressSet = true;
    }
    
    function mint(address _toAccount, uint256 _amount) override external {
        require(_msgSender() == protocolContract, "Only Gazzeth protocol contract can call this function");
        _mint(_toAccount, _amount); 
    }

    function burn(address _fromAccount, uint256 _amount) override external {
        if (_msgSender() != protocolContract && _fromAccount != _msgSender()) {
            uint256 decresedAllowance = allowance(_fromAccount, _msgSender()).sub(_amount, "Insufficient allowance");
            _approve(_fromAccount, _msgSender(), decresedAllowance);
        }
        _burn(_fromAccount, _amount);
    }
}
