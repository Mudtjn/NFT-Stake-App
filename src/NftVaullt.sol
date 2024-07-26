// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20; 

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol"; 

contract NftVault is Ownable {

    struct Nft {
        address nftAddress;
        uint256 tokenId;
        address previousOwner; 
        uint256 lastRewardTimeStamp; 
    }

    constructor() Ownable(msg.sender) {}

    
} 