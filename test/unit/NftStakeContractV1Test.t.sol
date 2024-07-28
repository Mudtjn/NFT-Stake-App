// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol"; 
import {DeployNftStakeContract} from "../../script/DeployNftStakeContract.s.sol";
import {NftStakeContractV1} from "../../src/NftStakeContractV1.sol";
import {NftVault} from "../../src/NftVault.sol";
import {StakeToken} from "../../src/StakeToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NftMock} from "../setup/NftMock.t.sol";

contract NftStakeContractV1Test is Test {

    NftVault nftVault; 
    StakeToken stakeToken; 
    address proxy; 
    NftStakeContractV1 nftStakeContractV1; 
    NftMock nftMock;

    address user = makeAddr("user"); 

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
        nftMock = new NftMock();  
    }

    function mintNftAndApprove(address to) public returns (uint256) {
        vm.startPrank(user); 
        uint256 tokenId = nftMock.mint(to); 
        nftMock.approve(address(proxy), tokenId); 
        vm.stopPrank(); 
        return tokenId;
    }

    function testContractOwnsVaultAndToken() public{
        assertEq(stakeToken.owner(), address(nftStakeContractV1)); 
        assertEq(nftVault.owner(), address(nftStakeContractV1)); 
    }

    function testContractAlreadyInitialized() public {
        NftStakeContractV1.StakeConfiguration memory testConfig; 
        vm.expectRevert();
        NftStakeContractV1(proxy).initialize(testConfig); 
    }

    function testInitialNoTokenDeployed() public {
        uint256 initialTokenId = NftStakeContractV1(proxy).getLatestTokenId();
        assertEq(initialTokenId, 0); 
    }

    function testUserCannotRestakeSameNft() public {
        uint256 tokenId = mintNftAndApprove(user); 
        vm.startPrank(user); 
        NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);  
        vm.stopPrank();       

        vm.startPrank(user);
        vm.expectRevert(); 
        NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId); 
        vm.stopPrank(); 
    }

    function testInformationUpdatedWhenStakeNft() public {
        uint256 initialBalance = stakeToken.balanceOf(user); 
        uint256 tokenId = mintNftAndApprove(user); 
        vm.prank(user); 
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);                
        NftStakeContractV1.NftStatus actualNftStatus = NftStakeContractV1(proxy).getNftStatusFromTokenId(vaultTokenId);  
        NftStakeContractV1.NftStatus expectedNftStatus = NftStakeContractV1.NftStatus.STAKED; 

        uint256 finalBalance = stakeToken.balanceOf(user); 
        uint256 expectedDifference = NftStakeContractV1(proxy).calculateRewards(vaultTokenId); 
        uint256 actualDifference = finalBalance - initialBalance; 
        uint256 latestTokenId = NftStakeContractV1(proxy).getLatestTokenId(); 

        assertEq(expectedDifference, actualDifference);
        assertEq(latestTokenId, vaultTokenId+1);
        assert(expectedNftStatus == actualNftStatus); 
    }

} 