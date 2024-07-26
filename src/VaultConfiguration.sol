// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20; 

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultConfiguration is Ownable {
    
    uint256 private s_rewards_per_block; 
    
    constructor() Ownable(msg.sender) {}

    function updateRewardsPerBlock(uint256 new_rewards_per_block) external onlyOwner {
        s_rewards_per_block = new_rewards_per_block; 
    }
}