// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";

contract Gazzeth is ERC20, ERC20Permit {

    modifier onlyProtocolContract() {
        require(_msgSender() == protocolContract, "Only Gazzeth protocol contract can call this function");
        _;
    }

    string constant NAME = "Gazzeth";
    string constant SYMBOL = "GZT";

    address owner;
    address protocolContract;
    bool protocolContractAddressSet;

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {
        owner = _msgSender();
    }

    function setProtocolContractAddress(address _protocolContract) external {
        require(_msgSender() == owner, "Only owner can call this function");
        require(!protocolContractAddressSet, "Protocol contract address already set");
        protocolContract = _protocolContract;
        protocolContractAddressSet = true;
    }
    
    //TODO: Check if it is preferred transfering from/to address(0)
    function mint(address _toAccount, uint256 _amount) external onlyProtocolContract() {
        _mint(_toAccount, _amount); 
    }

    function burn(address _fromAccount, uint256 _amount) external onlyProtocolContract() {
        _burn(_fromAccount, _amount);
    }
}
