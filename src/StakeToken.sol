// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Stake Token
 * @author Mudit Jain
 * @notice Reward token for users staking their NFTs
 */
contract StakeToken is ERC20, Ownable {
    error StakeToken__NotZeroAddress();
    error StakeToken__MustBeMoreThanZero();

    constructor() ERC20("StakeToken", "StT") Ownable(msg.sender) {}
    // mints token is the users account for staking
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (address(_to) == address(0)) revert StakeToken__NotZeroAddress();
        if (_amount == 0) revert StakeToken__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }
}
