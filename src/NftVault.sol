// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20; 

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title NftVault
 * @author Mudit Jain
 * @notice Vault which will store and transfer all the nfts received
 */
contract NftVault is Ownable {

    constructor() Ownable(msg.sender) {}

    function sendNft(address nftAddress, uint256 nftId, address to) external onlyOwner {
        IERC721(nftAddress).safeTransferFrom(address(this), to, nftId); 
    }
}