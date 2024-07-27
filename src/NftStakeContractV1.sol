// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {StakeToken} from "./StakeToken.sol";
import {NftVault} from "./NftVault.sol"; 
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Pausable, Context} from "@openzeppelin/contracts/utils/Pausable.sol"; 
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol"; 
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title NftStakeContract
 * @author Mudit Jain
 * @notice Nft Staking contract where users can stake their NFTs for rewards
 */
contract NftStakeContractV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, Pausable {

    error NftStakeContractV1__InvalidTokenId(); 
    error NftStakeContractV1__ZeroAddress(); 
    error NftStakeContractV1__NftStillStaked(uint256 tokenId); 
    error NftStakeContractV1__NftAlreadyUnstaked(uint256 tokenId); 
    error NftStakeContractV1__NftAlreadyWithdrawn(uint256 tokenId); 
    error NftStakeContractV1__CallerNotNftOwner(); 
    error NftStakeContractV1__DelayPeriodNotOver();
    error NftStakeContractV1__RewardAlreadyClaimed();

    struct Nft {
        address nftAddress;
        uint256 nftId;
        address previousOwner; 
        uint256 lastRewardTimeStamp; 
    }

    enum NftStatus {
        STAKED, 
        UNSTAKED, 
        WITHDRAWN
    }

    uint256 private s_rewards_per_block; 
    uint256 private s_tokenId; 
    uint256 private s_min_delay_between_rewards; 
    uint256 private s_unbonding_period; 
    StakeToken private stakeToken; 
    NftVault private nftvault; 
    mapping(uint256 tokenId => Nft depositedNft) private s_tokenId_to_nft;  
    mapping(uint256 tokenId => NftStatus) private s_tokenId_to_status;
    mapping(uint256 tokenId => uint256 unstakeTimeStamp) private s_tokenId_to_unstakeTime;

    event NftInitialized(); 

    event NftStaked(
        uint256 indexed tokenId, 
        address indexed owner
    );

    event NftUnstaked(
        uint256 indexed tokenId, 
        address indexed owner
    ); 

    event NftWithdrawn(
        uint256 indexed tokenId, 
        address indexed owner
    ); 

    modifier isValidTokenId(uint256 tokenId) {
        if(tokenId >= s_tokenId) revert NftStakeContractV1__InvalidTokenId();
        _; 
    }

    ///custom:oz-upgrades-unsafe-allow-constructor
    constructor(){
        _disableInitializers(); 
    }

    function transferOwnershipOfSubContracts(address upgradedContract) external onlyOwner{
        if(upgradedContract == address(0)) revert NftStakeContractV1__ZeroAddress(); 
        nftvault.transferOwnership(upgradedContract); 
        stakeToken.transferOwnership(upgradedContract); 
    }

    function stakeNft(
        address nftAddress, 
        uint256 nftId
    ) external whenNotPaused returns(uint256) {
        // checks 

        // effects
        uint256 tokenId = s_tokenId; 
        emit NftStaked(tokenId, msg.sender);

        // interactions
        s_tokenId_to_nft[tokenId] = Nft(nftAddress, nftId, msg.sender, block.timestamp);
        s_tokenId_to_status[tokenId] = NftStatus.STAKED; 
        IERC721(nftAddress).safeTransferFrom(msg.sender, address(nftvault), nftId); 
        s_tokenId++;
        return tokenId; 
    }

    function unStakeNft(uint256 tokenId) isValidTokenId(tokenId) external whenNotPaused {
        // checks
        Nft memory nft = s_tokenId_to_nft[tokenId];
        isCallerOwnerOfNft(nft, msg.sender); 
        NftStatus status = s_tokenId_to_status[tokenId]; 
        if(status == NftStatus.UNSTAKED) revert NftStakeContractV1__NftAlreadyUnstaked(tokenId); 
        if(status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId);

        // effects
        emit NftUnstaked(tokenId, nft.previousOwner); 
        
        // interactions
        s_tokenId_to_status[tokenId] = NftStatus.UNSTAKED;
        s_tokenId_to_unstakeTime[tokenId] = block.timestamp;  
    }

    function claimRewards(uint256 tokenId) isValidTokenId(tokenId) whenNotPaused external {
        // checks
        Nft storage nft = s_tokenId_to_nft[tokenId]; 
        isCallerOwnerOfNft(nft, msg.sender); 
        NftStatus status = s_tokenId_to_status[tokenId]; 
        
        // effects
        
        // interactions
        uint256 totalRewards = calculateRewardsAndUpdate(nft, status); 
        stakeToken.mint(msg.sender, totalRewards); 
    }

    function withdrawNft(uint256 tokenId) isValidTokenId(tokenId) external  {
        //checks 
        NftStatus status = s_tokenId_to_status[tokenId]; 
        if(status == NftStatus.STAKED) revert NftStakeContractV1__NftStillStaked(tokenId); 
        if(status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId); 
        Nft memory nft = s_tokenId_to_nft[tokenId];
        isCallerOwnerOfNft(nft, msg.sender); 
        //effects
        emit NftWithdrawn(tokenId, nft.previousOwner); 

        //interactions
        s_tokenId_to_status[tokenId] = NftStatus.WITHDRAWN; 
        nftvault.sendNft(nft.nftAddress, nft.nftId, nft.previousOwner); 
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        s_tokenId = 0;
    }

    function _authorizeUpgrade(address newImplementation) internal whenPaused override{}

    function getLatestTokenId() public view returns(uint256){
        return s_tokenId; 
    }

    function getNftFromTokenId(uint256 tokenId) isValidTokenId(tokenId) public view returns(Nft memory){
        return s_tokenId_to_nft[tokenId]; 
    }

    function getNftStatusFromTokenId(uint256 tokenId) isValidTokenId(tokenId) public view returns(NftStatus){
        return s_tokenId_to_status[tokenId]; 
    }

    function isCallerOwnerOfNft(Nft memory nft, address user) internal pure {
        if(nft.previousOwner != user) revert NftStakeContractV1__CallerNotNftOwner(); 
    }

    function calculateRewardsAndUpdate(Nft storage nft, NftStatus status) internal returns(uint256 totalRewards) {
        if( block.timestamp < nft.lastRewardTimeStamp ) revert NftStakeContractV1__RewardAlreadyClaimed();  
        if( (block.timestamp - nft.lastRewardTimeStamp) < s_min_delay_between_rewards ) revert NftStakeContractV1__DelayPeriodNotOver(); 
        if(status == NftStatus.STAKED){
            totalRewards = (block.timestamp - nft.lastRewardTimeStamp) * s_rewards_per_block; 
            nft.lastRewardTimeStamp = block.timestamp; 
        } else {
            totalRewards = (block.timestamp + s_unbonding_period - nft.lastRewardTimeStamp ) * s_rewards_per_block; 
            nft.lastRewardTimeStamp = block.timestamp + s_unbonding_period; 
        }   
    }

    function pauseContract() public onlyOwner {
        _pause(); 
    }

    function unpauseContract() public onlyOwner {
        _unpause(); 
    }

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return msg.sender;
    }

    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view override(Context, ContextUpgradeable) returns (uint256) {
        return 0;
    }

}
