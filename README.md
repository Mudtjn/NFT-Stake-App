## Nft Stake App

1. The application allows user to stake their NFTs (any ERC-721 compatible nft) and earn yield in form of tokens. The users can unstake their nfts and withdraw their nfts from the contract. 
2. The stakingContract implements UUPSUpgradeable Proxy where the implementation contract can be updated. 
3. The contract can be paused and unpaused according to owner's will. This centrality can be removed by use of DAO as the owner.
4. The owner can configure the rewards_received_per_block while the nft is staked.
5. There is a minimum period for which the nft cannot be unstaked after being staked. 
6. There is a minimum period `UnbondingPeriod` after which the unstakedNft can be withdrawn. 
7. The user who has staked the nft can redeem rewards multiple times, but there is atleast `minDelayBetweenRewards` between successive claims for redemption.   

### Additional functionality added
1. min delay between staking and unstaking period.
2. A second stake contract implementation is also created to show upgradeability. 

### About contracts
1. NftStakeContractV1 - original stake-contract implementation
2. NftStakeContractV1 - upgraded stake-contract implementation
3. NftVault - Vault to  store all staked nfts.
4. StakeToken - ERC20 contract to mint tokens. 

### Pausable contract
1. The admin can pause the contract, which would not allow users to stake nfts, unstake nfts and claim rewards. 
2. However, users can withdraw their unstaked nfts. 

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Copy `.env.example` into .env file and replace the respective fields with Urls and private keys.

1. On local chain,
   1. start local chain on anvil.
   2. Configure RPC_URL=http://127.0.0.1:8545  
   3. Configure PRIVATE_KEY to be one of anvils offered private keys
   4. On another terminal
```shell
$ source .env # loads enviroment variables
$ forge script script/DeployNftStakeContract.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast # deploys stakeToken, nftVault, NftStakeContractV1
$ forge script script/UpgradeNftStakeContract.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast # upgrades the smart contract implementation used by proxy 
```

2. On test network, 
   1. Configure RPC_URL= to your RPC_PROVIDER  
   2. Configure PRIVATE_KEY to be one of wallets private keys
```shell
$ source .env # loads enviroment variables
$ forge script script/DeployNftStakeContract.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast # deploys stakeToken, nftVault, NftStakeContractV1
$ forge script script/UpgradeNftStakeContract.s.sol --private-key $PRIVATE_KEY --rpc-url $RPC_URL --broadcast # upgrades the smart contract implementation used by proxy 
```

3. To interact with smart contract 
```shell
# to call read-only functions
$ cast call <contract_address> "functionName(type1,type2)" <arg1> <arg2>
# To send a transaction (for state-changing functions):
$ cast send <contract_address> "functionName(type1,type2)" <arg1> <arg2> --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY>
# To estimate gas for a transaction:
$ cast estimate <contract_address> "functionName(type1,type2)" <arg1> <arg2>
```