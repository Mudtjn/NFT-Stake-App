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
    event UnbondingPeriodUpdated(uint256 indexed unbondingPeriod); 
    event MinDelayBetweenStakeAndUnstakeUpdated(uint256 indexed minDelay);
    event RewardsPerBlockUpdated(uint256 indexed rewardsPerBlock); 
    event MinDelayBetweenRewardsUpdated(uint256 indexed minDelay);
    
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

        // updates staking timestamp in mapping
        s_tokenId_to_stakeTime[tokenId] = block.timestamp;
        // create new nft and stores it in mapping
        s_tokenId_to_nft[tokenId] = Nft(nftAddress, nftId, msg.sender, block.timestamp);
        // assign status for nft
        s_tokenId_to_status[tokenId] = NftStatus.STAKED;
        // transfer nft from user to nftVault
        IERC721(nftAddress).transferFrom(msg.sender, address(stakeConfiguration.nftvault), nftId);
        // update global token index
        stakeConfiguration.tokenId++;
        s_stake_configuration = stakeConfiguration;
        return tokenId;
    }

    /**
     * @notice un-stake nft
     * @param tokenId global token index of nft to unstake
     */
    function unstakeNft(uint256 tokenId) external isValidTokenId(tokenId) whenNotPaused {
        Nft memory nft = s_tokenId_to_nft[tokenId];
        // caller should be the one who staked the nft
        isCallerOwnerOfNft(nft, msg.sender);
        NftStatus status = s_tokenId_to_status[tokenId];
        // checks if the nft is still staked
        if (status == NftStatus.UNSTAKED) revert NftStakeContractV1__NftAlreadyUnstaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId);

        // checks that there is at least minimum delay between user staking an nft and unstaking an nft
        // if this check is not there then user does not just stake and unstake nft and redeems reward for unbonding period only
        if (block.timestamp - getStakeTimeFromTokenId(tokenId) < s_stake_configuration.minDelayBetweenStakeAndUnstake) {
            revert NftStakeContractV1__DelayPeriodBetweenStakeAndUnstakeNotOver();
        }

        emit NftUnstaked(tokenId, nft.previousOwner);

        // updtes information
        s_tokenId_to_status[tokenId] = NftStatus.UNSTAKED;
        s_tokenId_to_unstakeTime[tokenId] = block.timestamp;
    }

    /**
     * @notice user can claim reward for staked nfts and after unstaking rewards for unbonding rewards
     * @param tokenId global token index to redeem nfts 
     */
    function claimRewards(uint256 tokenId) external isValidTokenId(tokenId) whenNotPaused {
        Nft storage nft = s_tokenId_to_nft[tokenId];
        // does the person claiming the nft was the one who staked it
        isCallerOwnerOfNft(nft, msg.sender);
        NftStatus status = s_tokenId_to_status[tokenId];

        StakeToken stakeToken = s_stake_configuration.stakeToken;

        // calculates totalRewards that can be claimed till current block.timestamp
        // updates the latestRewardTimestamp for nfts
        uint256 totalRewards = calculateRewardsAndUpdate(nft, status, tokenId);
        // mints the reward for the user
        stakeToken.mint(msg.sender, totalRewards);
    }

    /**
     * @notice allows user to withdraw nft from the vault after unstaking it
     * @param tokenId global token id of nft user wants to withdraw
     */
    function withdrawNft(uint256 tokenId) external isValidTokenId(tokenId) {
        NftStatus status = s_tokenId_to_status[tokenId];
        Nft memory nft = s_tokenId_to_nft[tokenId];
        // checks user owns nft or not
        isCallerOwnerOfNft(nft, msg.sender);
        // checks if nft is unstaked or not
        if (status == NftStatus.STAKED) revert NftStakeContractV1__NftStillStaked(tokenId);
        if (status == NftStatus.WITHDRAWN) revert NftStakeContractV1__NftAlreadyWithdrawn(tokenId);
        uint256 unstakeTimeStamp = s_tokenId_to_unstakeTime[tokenId];
        uint256 unbondingPeriod = getUnbondingPeriod();
        // checks if the unbonding period has passed since unstaking
        if (block.timestamp < unstakeTimeStamp + unbondingPeriod) revert NftStakeContractV1__UnbondingPeriodNotOver();

        emit NftWithdrawn(tokenId, nft.previousOwner);

        // updates the status of nft
        s_tokenId_to_status[tokenId] = NftStatus.WITHDRAWN;
        // sends nft to the user
        s_stake_configuration.nftvault.sendNft(nft.nftAddress, nft.nftId, nft.previousOwner);
    }

    /**
     * @notice updates rewards per block
     * @param rewardsPerBlock new rewards per block
     */
    function updateRewardsPerBlock(uint256 rewardsPerBlock) external whenNotPaused onlyOwner returns (uint256) {
        if (rewardsPerBlock < MIN_REWARD_PER_BLOCK) revert NftStakeContractV1__RewardsPerBlockTooLow();
        emit RewardsPerBlockUpdated(rewardsPerBlock); 
        s_stake_configuration.rewardsPerBlock = rewardsPerBlock;
        return rewardsPerBlock;
    }

    /**
     * @notice updates minimum delay between rewards
     * @param minDelayBetweenRewards new new minimum delay
     */
    function updateMinDelayBetweenRewards(uint256 minDelayBetweenRewards)
        external
        whenNotPaused
        onlyOwner
        returns (uint256)
    {
        if (minDelayBetweenRewards < MIN_DELAY_BETWEEN_REWARDS) {
            revert NftStakeContractV1__MinDelayBetweenRewardsTooLow();
        }
        emit MinDelayBetweenRewardsUpdated(minDelayBetweenRewards); 
        s_stake_configuration.minDelayBetweenRewards = minDelayBetweenRewards;
        return minDelayBetweenRewards;
    }

    /**
     * @notice updates unbonding period
     * @param unbondingPeriod new unbonding period
     */
    function updateUnbondingPeriod(uint256 unbondingPeriod) external whenNotPaused onlyOwner returns (uint256) {
        if (unbondingPeriod < MIN_UNBONDING_PERIOD) revert NftStakeContractV1__UnbondingPeriodTooLow();
        emit UnbondingPeriodUpdated(unbondingPeriod);
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
        emit MinDelayBetweenStakeAndUnstakeUpdated(newDelayBetweenStakeAndUnstake); 
        s_stake_configuration.minDelayBetweenStakeAndUnstake = newDelayBetweenStakeAndUnstake;
        return newDelayBetweenStakeAndUnstake;
    }

    /**
     * @notice initialize contract configuration 
     * @param stakeConfiguration initial Staking contract configuration set by ADMIN
     */
    function initialize(StakeConfiguration memory stakeConfiguration) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        if (stakeConfiguration.rewardsPerBlock < MIN_REWARD_PER_BLOCK) revert NftStakeContractV1__RewardsPerBlockTooLow();
        if (stakeConfiguration.minDelayBetweenRewards < MIN_DELAY_BETWEEN_REWARDS) {
            revert NftStakeContractV1__MinDelayBetweenRewardsTooLow();
        }
        if (stakeConfiguration.unbondingPeriod < MIN_UNBONDING_PERIOD) revert NftStakeContractV1__UnbondingPeriodTooLow();
        if (stakeConfiguration.minDelayBetweenStakeAndUnstake < MIN_DELAY_BETWEEN_STAKE_AND_UNSTAKE) {
            revert NftStakeContractV1__MinDelayStakeAndUnstakeTooLow();
        }
        s_stake_configuration = stakeConfiguration;
    }

    /**
     * to pause the functionality of contract
     * only unstaked nfts can be withdrawn during this period
     * contract also needs to be paused while upgrading
     */
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
    /// @notice function this is version 1 of contract 
    function version() public pure returns (uint256) {
        return 1;
    }
}
