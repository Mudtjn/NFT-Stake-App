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
    error NftStakeContractV1__RewardsPerBlockTooLow();
    error NftStakeContractV1__UnbondingPeriodTooLow();
    error NftStakeContractV1__MinDelayBetweenRewardsTooLow();
    error NftStakeContractV1__UnbondingPeriodNotOver();
    error NftStakeContractV1__DelayPeriodBetweenStakeAndUnstakeNotOver();
    error NftStakeContractV1__MinDelayStakeAndUnstakeTooLow();

    /// @notice This struct store configuration of nfts that have been staked on the platform
    struct Nft {
        /// @notice ERC721 contract address
        address nftAddress;
        /// @notice token-id of nft
        uint256 nftId;
        /// @notice the user who staked the nft
        address previousOwner;
        /// @notice last timestamp when user claimed rewards
        uint256 lastRewardTimeStamp;
    }

    /// @notice This struct stores the configuration for the contract
    struct StakeConfiguration {
        /// @notice rewardPerBlock given to the the staker
        uint256 rewardsPerBlock;
        /// @notice globalTokenId for nfts sent to the user
        uint256 tokenId;
        /// @notice minimum delay after which user can redeem rewards
        uint256 minDelayBetweenRewards;
        /// @notice minimum time after unstaking after which user can withdraw nft
        uint256 unbondingPeriod;
        /// @notice minimum delat after which user can unstake their nft
        uint256 minDelayBetweenStakeAndUnstake;
        /// @notice token distributed as reward
        StakeToken stakeToken;
        /// @notice nftVault which stores nfts
        NftVault nftvault;
    }

    /// @notice Nft status
    enum NftStatus {
        STAKED,
        UNSTAKED,
        WITHDRAWN
    }

    // @notice these constants are there to prevent DoS or high traffic for claiming rewards and unstaking
    uint256 public constant MIN_REWARD_PER_BLOCK = 1e9;
    uint256 public constant MIN_DELAY_BETWEEN_REWARDS = 1 days;
    uint256 public constant MIN_UNBONDING_PERIOD = 1 days;
    uint256 public constant MIN_DELAY_BETWEEN_STAKE_AND_UNSTAKE = 1 days;

    /// @notice configuration
    StakeConfiguration private s_stake_configuration;
    /// @notice token-id to nft mapping
    mapping(uint256 tokenId => Nft) s_tokenId_to_nft;
    /// @notice token-id to nft status
    mapping(uint256 tokenId => NftStatus) private s_tokenId_to_status;
    /// @notice token-id to timestamp nft was staked
    mapping(uint256 tokenId => uint256 stakeTimestamp) private s_tokenId_to_stakeTime;
    /// @notice token-id to timestamp nft was unstaked
    mapping(uint256 tokenId => uint256 unstakeTimestamp) private s_tokenId_to_unstakeTime;

    event NftInitialized();

    event NftStaked(uint256 indexed tokenId, address indexed owner);

    event NftUnstaked(uint256 indexed tokenId, address indexed owner);

    event NftWithdrawn(uint256 indexed tokenId, address indexed owner);
    /// @notice checks if token-id provided by user is valid or out-of-bounds
    modifier isValidTokenId(uint256 tokenId) {
        if (tokenId >= s_stake_configuration.tokenId) revert NftStakeContractV1__InvalidTokenId();
        _;
    }

    ///custom:oz-upgrades-unsafe-allow-constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice stakes a user-nft by transferring the nft to nftVault
     * @param nftAddress address of ERC721Contract
     * @param nftId token-id of nft in ERC721 contract
     * @return token-id of nft staked
     */
    function stakeNft(address nftAddress, uint256 nftId) external whenNotPaused returns (uint256) {
        // check if user owns provided nft
        if (IERC721(nftAddress).ownerOf(nftId) != msg.sender) revert NftStakeContractV1__CallerNotNftOwner();

        StakeConfiguration memory stakeConfiguration = s_stake_configuration;
        uint256 tokenId = s_stake_configuration.tokenId;
        emit NftStaked(tokenId, msg.sender);

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
        if (status == NftStatus.UNSTAKED) revert NftStakeContractV1__NftAlreadyUnstaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId);

        if (block.timestamp - getStakeTimeFromTokenId(tokenId) < s_stake_configuration.minDelayBetweenStakeAndUnstake) {
            revert NftStakeContractV1__DelayPeriodBetweenStakeAndUnstakeNotOver();
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
        if (status == NftStatus.STAKED) revert NftStakeContractV1__NftStillStaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId);
        uint256 unstakeTimeStamp = s_tokenId_to_unstakeTime[tokenId];
        uint256 unbondingPeriod = getUnbondingPeriod();
        if (block.timestamp < unstakeTimeStamp + unbondingPeriod) revert NftStakeContractV1__UnbondingPeriodNotOver();
        //effects
        emit NftWithdrawn(tokenId, nft.previousOwner);

        //interactions
        s_tokenId_to_status[tokenId] = NftStatus.WITHDRAWN;
        s_stake_configuration.nftvault.sendNft(nft.nftAddress, nft.nftId, nft.previousOwner);
    }

    function updateRewardsPerBlock(uint256 rewardsPerBlock) external whenNotPaused onlyOwner returns (uint256) {
        if (rewardsPerBlock < MIN_REWARD_PER_BLOCK) revert NftStakeContractV1__RewardsPerBlockTooLow();
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
            revert NftStakeContractV1__MinDelayBetweenRewardsTooLow();
        }
        s_stake_configuration.minDelayBetweenRewards = minDelayBetweenRewards;
        return minDelayBetweenRewards;
    }

    function updateUnbondingPeriod(uint256 unbondingPeriod) external whenNotPaused onlyOwner returns (uint256) {
        if (unbondingPeriod < MIN_UNBONDING_PERIOD) revert NftStakeContractV1__UnbondingPeriodTooLow();
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
            revert NftStakeContractV1__MinDelayStakeAndUnstakeTooLow();
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
        if (nft.previousOwner != user) revert NftStakeContractV1__CallerNotNftOwner();
    }

    function calculateRewardsAndUpdate(Nft storage nft, NftStatus status, uint256 tokenId)
        internal
        returns (uint256 totalRewards)
    {
        StakeConfiguration memory stakeConfig = s_stake_configuration;
        if (block.timestamp < nft.lastRewardTimeStamp) revert NftStakeContractV1__RewardAlreadyClaimed();
        if ((block.timestamp - nft.lastRewardTimeStamp) < stakeConfig.minDelayBetweenRewards) {
            revert NftStakeContractV1__DelayPeriodNotOver();
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
        return 1;
    }
}
