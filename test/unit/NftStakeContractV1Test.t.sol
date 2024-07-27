// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol"; 
import {DeployNftStakeContract} from "../../script/DeployNftStakeContract.s.sol";
import {NftStakeContractV1} from "../../src/NftStakeContractV1.sol";
import {NftVault} from "../../src/NftVault.sol";
import {StakeToken} from "../../src/StakeToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC721Mock} from "@openzeppelin/contracts/"

contract NftStakeContractV1Test is Test {

    NftVault nftVault; 
    StakeToken stakeToken; 
    address proxy; 
    NftStakeContractV1 nftStakeContractV1; 

    function setUp() public {
        DeployNftStakeContract deployStakeContractScript = new DeployNftStakeContract(); 
        address proxyAddress; 
        address nftStakeContractV1Address ;      
        address nftVaultAddress; 
        address stakeTokenAddress; 
        (proxyAddress, nftStakeContractV1Address, nftVaultAddress, stakeTokenAddress) = deployStakeContractScript.run(); 
        proxy = proxyAddress; 
        nftStakeContractV1 = NftStakeContractV1(nftStakeContractV1Address); 
        stakeToken = StakeToken(stakeTokenAddress); 
        nftVault = NftVault(nftVaultAddress); 
    }

    function testContractOwnsVaultAndToken() public{
        assertEq(stakeToken.owner(), address(nftStakeContractV1)); 
        assertEq(nftVault.owner(), address(nftStakeContractV1)); 
    }

    function testContractAlreadyInitialized() public {
        vm.expectRevert();
        NftStakeContractV1(proxy).initialize(); 
    }

    function testInitialNoTokenDeployed() public {
        uint256 initialTokenId = NftStakeContractV1(proxy).getLatestTokenId();
        assertEq(initialTokenId, 0); 
    }

      
} 