// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployNftStakeContract} from "../script/DeployNftStakeContract.s.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {NftVault} from "../src/NftVault.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NftMock} from "./setup/NftMock.t.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
        address nftStakeContractV1Address;
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
        vm.startPrank(to);
        uint256 tokenId = nftMock.mint(to);
        nftMock.approve(address(proxy), tokenId);
        vm.stopPrank();
        return tokenId;
    }

    function causeDelayAndMove(uint256 delay) public {
        vm.warp(block.timestamp + delay);
        vm.roll(1);
    }

    ////////////////// INITIAL CONFIGURATION ///////////////////////////////

    function testContractOwnsVaultAndToken() public view {
        assertEq(stakeToken.owner(), proxy);
        assertEq(nftVault.owner(), proxy);
    }

    function testContractAlreadyInitialized() public {
        NftStakeContractV1.StakeConfiguration memory testConfig;
        vm.expectRevert();
        NftStakeContractV1(proxy).initialize(testConfig);
    }

    function testInitialNoTokenDeployed() public view {
        uint256 initialTokenId = NftStakeContractV1(proxy).getLatestTokenId();
        assertEq(initialTokenId, 0);
    }

    /////////////////// STAKE NFT ///////////////////////////////////////////

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
        assertEq(latestTokenId, vaultTokenId + 1);
        assert(expectedNftStatus == actualNftStatus);
    }

    function testStakedNftsTransferredToNftVault() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        assertEq(nftMock.ownerOf(tokenId), address(nftVault));
    }

    function testStakeFailsWhenContractPaused() public {
        vm.prank(NftStakeContractV1(proxy).owner());
        NftStakeContractV1(proxy).pauseContract();

        uint256 tokenId = mintNftAndApprove(user);
        vm.startPrank(user);
        vm.expectRevert();
        NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.stopPrank();
    }

    function testNftStakeRevertsOnInvalidTokenId() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
    
        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenRewards()); 
        vm.startPrank(user); 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__InvalidTokenId.selector); 
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId+1); 
        vm.stopPrank(); 
    }

    //////////////////// CLAIM REWARDS ///////////////////////////////////
    function testUserCannotCollectRewardsBeforeMinDelay() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.startPrank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__DelayPeriodNotOver.selector);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
        vm.stopPrank();
    }

    function testAttackerCannotWithdrawUserRewards() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__CallerNotNftOwner.selector);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
    }

    function testClaimRewardsUpdatesUserBalanceAndInformation() public {
        uint256 initialBalance = stakeToken.balanceOf(user);
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenRewards());
        uint256 expectedRewards = NftStakeContractV1(proxy).calculateRewards(vaultTokenId);

        vm.prank(user);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
        uint256 finalBalance = stakeToken.balanceOf(user);

        vm.startPrank(user);
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__DelayPeriodNotOver.selector);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
        vm.stopPrank();
        assertEq(expectedRewards, finalBalance - initialBalance);
    }

    function testRewardClaimedIsCorrectAndNoMoreCoinsAfterUnbondingPeriod() public {
        uint256 initialBalance = stakeToken.balanceOf(user);
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        uint256 minDelayBetweenRewards = NftStakeContractV1(proxy).getMinDelayBetweenRewards();
        uint256 unbondingPeriod = NftStakeContractV1(proxy).getUnbondingPeriod();

        causeDelayAndMove(minDelayBetweenRewards);
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        causeDelayAndMove(2 * unbondingPeriod);
        vm.prank(user);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);

        uint256 expectedRewards =
            (unbondingPeriod + minDelayBetweenRewards) * NftStakeContractV1(proxy).getRewardsPerBlock();
        uint256 finalBalance = stakeToken.balanceOf(user);
        assertEq(expectedRewards, finalBalance - initialBalance);
        assertEq(NftStakeContractV1(proxy).calculateRewards(vaultTokenId), 0);
    }

    function testRewardsCanBeClaimedAfterNftIsWithdrawn() public {
        uint256 initialBalance = stakeToken.balanceOf(user);
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        uint256 minDelayBetweenRewards = NftStakeContractV1(proxy).getMinDelayBetweenRewards();
        uint256 unbondingPeriod = NftStakeContractV1(proxy).getUnbondingPeriod();

        causeDelayAndMove(minDelayBetweenRewards);
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        causeDelayAndMove(2 * unbondingPeriod);
        vm.startPrank(user);
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId); 
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
        vm.stopPrank();

        uint256 expectedRewards =
            (unbondingPeriod + minDelayBetweenRewards) * NftStakeContractV1(proxy).getRewardsPerBlock();
        uint256 finalBalance = stakeToken.balanceOf(user);
        assertEq(expectedRewards, finalBalance - initialBalance);
        assertEq(NftStakeContractV1(proxy).calculateRewards(vaultTokenId), 0);
    }

    function testClaimRewardsFailsWhenContractPaused() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.startPrank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.stopPrank();

        vm.prank(NftStakeContractV1(proxy).owner());
        NftStakeContractV1(proxy).pauseContract();

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenRewards());
        vm.startPrank(user);
        vm.expectRevert();
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
        vm.stopPrank();
    }

    ///////////////// UNSTAKE NFT ///////////////////////////////////////
    function testAttackerNotAllowedToUnstakeUserNfts() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__CallerNotNftOwner.selector);
        NftStakeContractV1(proxy).claimRewards(vaultTokenId);
    }

    function testAlreadyUnstakedNftsCannotBeUnstakedAgain() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NftStakeContractV1.NftStakeContractV1__NftAlreadyUnstaked.selector, vaultTokenId)
        );
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);
        vm.stopPrank();
    }

    function testNftsCannotBeUnstakedBeforeMinDelay() public {
        uint256 tokenId = mintNftAndApprove(user); 
        vm.startPrank(user); 
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId); 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__DelayPeriodBetweenStakeAndUnstakeNotOver.selector); 
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId); 
        vm.stopPrank(); 
    }

    function testUnstakeNftUpdatesInformationForStatusAndUnstakeTime() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        assert(NftStakeContractV1(proxy).getNftStatusFromTokenId(vaultTokenId) == NftStakeContractV1.NftStatus.UNSTAKED);
        assert(NftStakeContractV1(proxy).getUnstakeTimestampFromTokenId(vaultTokenId) == block.timestamp);
    }

    function testUnstakedNftCannotBeStakedBeforeWithdraw() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__CallerNotNftOwner.selector);
        NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.stopPrank();
    }

    function testUnstakeFailsWhenContractPaused() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.startPrank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.stopPrank();

        vm.prank(NftStakeContractV1(proxy).owner());
        NftStakeContractV1(proxy).pauseContract();

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.startPrank(user);
        vm.expectRevert();
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);
        vm.stopPrank();
    }

    //////////////// WITHDRAW NFT ////////////////////////////////////////
    function testAttackerNotAllowedToWithdrawUserNfts() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__CallerNotNftOwner.selector);
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId);
    }

    function testWithdrawNftFailsForStakedNfts() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.startPrank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);
        vm.expectRevert(
            abi.encodeWithSelector(NftStakeContractV1.NftStakeContractV1__NftStillStaked.selector, vaultTokenId)
        );
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId);
        vm.stopPrank();
    }

    function testWithdrawNftFailsBeforeUnbondingPeriod() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        vm.startPrank(user);
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__UnbondingPeriodNotOver.selector);
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId);
        vm.stopPrank();
    }

    function testWithdrawNftUpdatesInformationCorrectly() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user);
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock), tokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake());
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        causeDelayAndMove(NftStakeContractV1(proxy).getUnbondingPeriod());
        vm.prank(user);
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId);

        NftStakeContractV1.NftStatus expectedNftStatus = NftStakeContractV1.NftStatus.WITHDRAWN;
        NftStakeContractV1.NftStatus actualNftStatus = NftStakeContractV1(proxy).getNftStatusFromTokenId(vaultTokenId);
        assert(expectedNftStatus == actualNftStatus);
        assertEq(nftMock.ownerOf(tokenId), user);
    }

    function testNftWithdrawalWorksEvenWhenContractPaused() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user); 
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock),tokenId); 

        causeDelayAndMove(NftStakeContractV1(proxy).getMinDelayBetweenStakeAndUnstake()); 
        vm.prank(user);
        NftStakeContractV1(proxy).unstakeNft(vaultTokenId);

        vm.prank(NftStakeContractV1(proxy).owner()); 
        NftStakeContractV1(proxy).pauseContract(); 

        causeDelayAndMove(NftStakeContractV1(proxy).getUnbondingPeriod()); 
        vm.prank(user); 
        NftStakeContractV1(proxy).withdrawNft(vaultTokenId); 
        assertEq(nftMock.ownerOf(tokenId), user);  
    }

    ///////////////////////////// update function ////////////////////////////
    function testStakeConfigurationCannotBeUpdatedByNonOwner() public {
        vm.startPrank(user); 
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user)); 
        NftStakeContractV1(proxy).updateRewardsPerBlock(1e6);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user)); 
        NftStakeContractV1(proxy).updateMinDelayBetweenRewards(1e6); 
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user)); 
        NftStakeContractV1(proxy).updateMinDelayBetweenStakeAndUnstake(1e6);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        NftStakeContractV1(proxy).updateUnbondingPeriod(1e6); 
        vm.stopPrank();
    }

    function testStakeConfigurationCannotBeUpdatedLessThanMinValue() public {
        vm.startPrank(NftStakeContractV1(proxy).owner()); 
        uint256 updatedRewardsPerBlock = NftStakeContractV1(proxy).MIN_REWARD_PER_BLOCK()/2; 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__RewardsPerBlockTooLow.selector); 
        NftStakeContractV1(proxy).updateRewardsPerBlock(updatedRewardsPerBlock);
        uint256 updatedMinDelayBetweenStakeAndUnstake = NftStakeContractV1(proxy).MIN_DELAY_BETWEEN_STAKE_AND_UNSTAKE()/2; 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__MinDelayStakeAndUnstakeTooLow.selector); 
        NftStakeContractV1(proxy).updateMinDelayBetweenStakeAndUnstake(updatedMinDelayBetweenStakeAndUnstake); 
        uint256 updatedUnbondingPeriod = NftStakeContractV1(proxy).MIN_UNBONDING_PERIOD()/2; 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__UnbondingPeriodTooLow.selector); 
        NftStakeContractV1(proxy).updateUnbondingPeriod(updatedUnbondingPeriod);
        uint256 updatedMinDelayBetweenRewards = NftStakeContractV1(proxy).MIN_DELAY_BETWEEN_REWARDS()/2; 
        vm.expectRevert(NftStakeContractV1.NftStakeContractV1__MinDelayBetweenRewardsTooLow.selector); 
        NftStakeContractV1(proxy).updateMinDelayBetweenRewards(updatedMinDelayBetweenRewards);  
        vm.stopPrank(); 
    }

    ////////////////////////////// getters ///////////////////////
    function testGetnftFromTokenId() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user); 
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock),tokenId);         

        NftStakeContractV1.Nft memory nft = NftStakeContractV1(proxy).getNftFromTokenId(vaultTokenId); 
        assertEq(nft.nftAddress, address(nftMock));
        assertEq(nft.nftId, vaultTokenId);  
    }

    function testGetStakeTimeFromTokenId() public {
        uint256 tokenId = mintNftAndApprove(user);
        vm.prank(user); 
        uint256 vaultTokenId = NftStakeContractV1(proxy).stakeNft(address(nftMock),tokenId);         

        assertEq(NftStakeContractV1(proxy).getStakeTimeFromTokenId(vaultTokenId), block.timestamp);
    }

    function testOnlyOwnerCanUnlockContract() public {
        vm.prank(NftStakeContractV1(proxy).owner()); 
        NftStakeContractV1(proxy).pauseContract(); 

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));  
        NftStakeContractV1(proxy).unpauseContract(); 
        vm.stopPrank();
    }
}
