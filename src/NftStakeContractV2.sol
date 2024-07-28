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
contract NftStakeContractV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, Pausable {
    error NftStakeContractV2__InvalidTokenId();
    error NftStakeContractV2__ZeroAddress();
    error NftStakeContractV2__NftStillStaked(uint256 tokenId);
    error NftStakeContractV2__NftAlreadyUnstaked(uint256 tokenId);
    error NftStakeContractV2__NftAlreadyWithdrawn(uint256 tokenId);
    error NftStakeContractV2__CallerNotNftOwner();
    error NftStakeContractV2__DelayPeriodNotOver();
    error NftStakeContractV2__RewardAlreadyClaimed();
    error NftStakeContractV2__RewardsPerBlockTooLow();
    error NftStakeContractV2__UnbondingPeriodTooLow();
    error NftStakeContractV2__MinDelayBetweenRewardsTooLow();
    error NftStakeContractV2__UnbondingPeriodNotOver();
    error NftStakeContractV2__DelayPeriodBetweenStakeAndUnstakeNotOver();
    error NftStakeContractV2__MinDelayStakeAndUnstakeTooLow();

    struct Nft {
        address nftAddress;
        uint256 nftId;
        address previousOwner;
        uint256 lastRewardTimeStamp;
    }

    struct StakeConfiguration {
        uint256 rewardsPerBlock;
        uint256 tokenId;
        uint256 minDelayBetweenRewards;
        uint256 unbondingPeriod;
        uint256 minDelayBetweenStakeAndUnstake;
        StakeToken stakeToken;
        NftVault nftvault;
    }

    enum NftStatus {
        STAKED,
        UNSTAKED,
        WITHDRAWN
    }

    uint256 public constant MIN_REWARD_PER_BLOCK = 1e9;
    uint256 public constant MIN_DELAY_BETWEEN_REWARDS = 1 days;
    uint256 public constant MIN_UNBONDING_PERIOD = 1 days;
    uint256 public constant MIN_DELAY_BETWEEN_STAKE_AND_UNSTAKE = 1 days;
    StakeConfiguration private s_stake_configuration;
    mapping(uint256 tokenId => Nft) s_tokenId_to_nft;
    mapping(uint256 tokenId => NftStatus) private s_tokenId_to_status;
    mapping(uint256 tokenId => uint256 stakeTimestamp) private s_tokenId_to_stakeTime;
    mapping(uint256 tokenId => uint256 unstakeTimestamp) private s_tokenId_to_unstakeTime;

    event NftInitialized();

    event NftStaked(uint256 indexed tokenId, address indexed owner);

    event NftUnstaked(uint256 indexed tokenId, address indexed owner);

    event NftWithdrawn(uint256 indexed tokenId, address indexed owner);

    modifier isValidTokenId(uint256 tokenId) {
        if (tokenId >= s_stake_configuration.tokenId) revert NftStakeContractV2__InvalidTokenId();
        _;
    }

    ///custom:oz-upgrades-unsafe-allow-constructor
    constructor() {
        _disableInitializers();
    }

    function stakeNft(address nftAddress, uint256 nftId) external whenNotPaused returns (uint256) {
        // checks
        if (IERC721(nftAddress).ownerOf(nftId) != msg.sender) revert NftStakeContractV2__CallerNotNftOwner();

        // effects
        StakeConfiguration memory stakeConfiguration = s_stake_configuration;
        uint256 tokenId = s_stake_configuration.tokenId;
        emit NftStaked(tokenId, msg.sender);

        // interactions
        s_tokenId_to_stakeTime[tokenId] = block.timestamp;
        s_tokenId_to_nft[tokenId] = Nft(nftAddress, nftId, msg.sender, block.timestamp);
        s_tokenId_to_status[tokenId] = NftStatus.STAKED;
        IERC721(nftAddress).transferFrom(msg.sender, address(stakeConfiguration.nftvault), nftId);
        stakeConfiguration.tokenId++;
        s_stake_configuration = stakeConfiguration;
        return tokenId;
    }

    function unstakeNft(uint256 tokenId) external isValidTokenId(tokenId) whenNotPaused {
        // checks
        Nft memory nft = s_tokenId_to_nft[tokenId];
        isCallerOwnerOfNft(nft, msg.sender);
        NftStatus status = s_tokenId_to_status[tokenId];
        if (status == NftStatus.UNSTAKED) revert NftStakeContractV2__NftAlreadyUnstaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV2__NftAlreadyWithdrawn(tokenId);

        if (block.timestamp - getStakeTimeFromTokenId(tokenId) < s_stake_configuration.minDelayBetweenStakeAndUnstake) {
            revert NftStakeContractV2__DelayPeriodBetweenStakeAndUnstakeNotOver();
        }

        // effects
        emit NftUnstaked(tokenId, nft.previousOwner);

        // interactions
        s_tokenId_to_status[tokenId] = NftStatus.UNSTAKED;
        s_tokenId_to_unstakeTime[tokenId] = block.timestamp;
    }

    function claimRewards(uint256 tokenId) external isValidTokenId(tokenId) whenNotPaused {
        // checks
        Nft storage nft = s_tokenId_to_nft[tokenId];
        isCallerOwnerOfNft(nft, msg.sender);
        NftStatus status = s_tokenId_to_status[tokenId];
        // effects
        StakeToken stakeToken = s_stake_configuration.stakeToken;
        // interactions
        uint256 totalRewards = calculateRewardsAndUpdate(nft, status, tokenId);
        stakeToken.mint(msg.sender, totalRewards);
    }

    function withdrawNft(uint256 tokenId) external isValidTokenId(tokenId) {
        //checks
        NftStatus status = s_tokenId_to_status[tokenId];
        Nft memory nft = s_tokenId_to_nft[tokenId];
        isCallerOwnerOfNft(nft, msg.sender);
        if (status == NftStatus.STAKED) revert NftStakeContractV2__NftStillStaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV2__NftAlreadyWithdrawn(tokenId);
        uint256 unstakeTimeStamp = s_tokenId_to_unstakeTime[tokenId];
        uint256 unbondingPeriod = getUnbondingPeriod();
        if (block.timestamp < unstakeTimeStamp + unbondingPeriod) revert NftStakeContractV2__UnbondingPeriodNotOver();
        //effects
        emit NftWithdrawn(tokenId, nft.previousOwner);

        //interactions
        s_tokenId_to_status[tokenId] = NftStatus.WITHDRAWN;
        s_stake_configuration.nftvault.sendNft(nft.nftAddress, nft.nftId, nft.previousOwner);
    }

    function updateRewardsPerBlock(uint256 rewardsPerBlock) external whenNotPaused onlyOwner returns (uint256) {
        if (rewardsPerBlock < MIN_REWARD_PER_BLOCK) revert NftStakeContractV2__RewardsPerBlockTooLow();
        s_stake_configuration.rewardsPerBlock = rewardsPerBlock;
        return rewardsPerBlock;
    }

    function updateMinDelayBetweenRewards(uint256 minDelayBetweenRewards)
        external
        whenNotPaused
        onlyOwner
        returns (uint256)
    {
        if (minDelayBetweenRewards < MIN_DELAY_BETWEEN_REWARDS) {
            revert NftStakeContractV2__MinDelayBetweenRewardsTooLow();
        }
        s_stake_configuration.minDelayBetweenRewards = minDelayBetweenRewards;
        return minDelayBetweenRewards;
    }

    function updateUnbondingPeriod(uint256 unbondingPeriod) external whenNotPaused onlyOwner returns (uint256) {
        if (unbondingPeriod < MIN_UNBONDING_PERIOD) revert NftStakeContractV2__UnbondingPeriodTooLow();
        s_stake_configuration.unbondingPeriod = unbondingPeriod;
        return unbondingPeriod;
    }

    function updateMinDelayBetweenStakeAndUnstake(uint256 newDelayBetweenStakeAndUnstake)
        external
        whenNotPaused
        onlyOwner
        returns (uint256)
    {
        if (newDelayBetweenStakeAndUnstake < MIN_DELAY_BETWEEN_STAKE_AND_UNSTAKE) {
            revert NftStakeContractV2__MinDelayStakeAndUnstakeTooLow();
        }
        s_stake_configuration.minDelayBetweenStakeAndUnstake = newDelayBetweenStakeAndUnstake;
        return newDelayBetweenStakeAndUnstake;
    }

    function initialize(StakeConfiguration memory stakeConfiguration) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        s_stake_configuration = stakeConfiguration;
    }

    function pauseContract() public onlyOwner {
        _pause();
    }

    function unpauseContract() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override whenPaused {}

    function isCallerOwnerOfNft(Nft memory nft, address user) internal pure {
        if (nft.previousOwner != user) revert NftStakeContractV2__CallerNotNftOwner();
    }

    function calculateRewardsAndUpdate(Nft storage nft, NftStatus status, uint256 tokenId)
        internal
        returns (uint256 totalRewards)
    {
        StakeConfiguration memory stakeConfig = s_stake_configuration;
        if (block.timestamp < nft.lastRewardTimeStamp) revert NftStakeContractV2__RewardAlreadyClaimed();
        if ((block.timestamp - nft.lastRewardTimeStamp) < stakeConfig.minDelayBetweenRewards) {
            revert NftStakeContractV2__DelayPeriodNotOver();
        }
        if (status == NftStatus.STAKED) {
            totalRewards = (block.timestamp - nft.lastRewardTimeStamp) * stakeConfig.rewardsPerBlock;
            nft.lastRewardTimeStamp = block.timestamp;
        } else {
            uint256 unstakeTime = s_tokenId_to_unstakeTime[tokenId];
            totalRewards =
                (unstakeTime + stakeConfig.unbondingPeriod - nft.lastRewardTimeStamp) * stakeConfig.rewardsPerBlock;
            nft.lastRewardTimeStamp = unstakeTime + stakeConfig.unbondingPeriod;
        }
        s_stake_configuration = stakeConfig;
    }

    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return msg.sender;
    }

    function _msgData() internal pure override(Context, ContextUpgradeable) returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal pure override(Context, ContextUpgradeable) returns (uint256) {
        return 0;
    }

    function calculateRewards(uint256 tokenId) public view isValidTokenId(tokenId) returns (uint256 totalRewards) {
        StakeConfiguration memory stakeConfig = s_stake_configuration;
        Nft memory nft = s_tokenId_to_nft[tokenId];
        NftStatus status = s_tokenId_to_status[tokenId];
        if (status == NftStatus.STAKED) {
            totalRewards = (block.timestamp - nft.lastRewardTimeStamp) * stakeConfig.rewardsPerBlock;
        } else {
            uint256 unstakeTime = s_tokenId_to_unstakeTime[tokenId];
            totalRewards =
                (unstakeTime + stakeConfig.unbondingPeriod - nft.lastRewardTimeStamp) * stakeConfig.rewardsPerBlock;
        }
    }

    function getLatestTokenId() public view returns (uint256) {
        return s_stake_configuration.tokenId;
    }

    function getStakeTimeFromTokenId(uint256 tokenId) public view isValidTokenId(tokenId) returns (uint256) {
        return s_tokenId_to_stakeTime[tokenId];
    }

    function getNftFromTokenId(uint256 tokenId) public view isValidTokenId(tokenId) returns (Nft memory) {
        return s_tokenId_to_nft[tokenId];
    }

    function getNftStatusFromTokenId(uint256 tokenId) public view isValidTokenId(tokenId) returns (NftStatus) {
        return s_tokenId_to_status[tokenId];
    }

    function getUnstakeTimestampFromTokenId(uint256 tokenId) public view isValidTokenId(tokenId) returns (uint256) {
        return s_tokenId_to_unstakeTime[tokenId];
    }

    function getRewardsPerBlock() public view returns (uint256) {
        return s_stake_configuration.rewardsPerBlock;
    }

    function getMinDelayBetweenRewards() public view returns (uint256) {
        return s_stake_configuration.minDelayBetweenRewards;
    }

    function getUnbondingPeriod() public view returns (uint256) {
        return s_stake_configuration.unbondingPeriod;
    }

    function getMinDelayBetweenStakeAndUnstake() public view returns (uint256) {
        return s_stake_configuration.minDelayBetweenStakeAndUnstake;
    }

    function version() public pure returns (uint256) {
        return 2;
    }

    function test() public {}
}
