// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NftMock is ERC721 {
    uint256 private s_tokenId = 0;

    constructor() ERC721("MockNft", "MNT") {}

    function mint(address _to) public returns (uint256) {
        _mint(_to, s_tokenId);
        uint256 tokenId = s_tokenId;
        s_tokenId++;
        return tokenId;
    }

    function test() public {}
}
