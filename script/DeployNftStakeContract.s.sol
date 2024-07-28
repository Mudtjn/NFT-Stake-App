// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {NftVault} from "../src/NftVault.sol";

contract DeployNftStakeContract is Script {
    NftVault nftVault;
    StakeToken stakeToken;

    function run() external returns (address, address, address, address) {
        (address proxy, address nftStakeContractV1) = deployNftStakeContract();
        return (proxy, nftStakeContractV1, address(nftVault), address(stakeToken));
    }

    function deployNftStakeContract() public returns (address, address) {
        vm.startBroadcast();
        stakeToken = new StakeToken();
        nftVault = new NftVault();
        vm.stopBroadcast();

        NftStakeContractV1.StakeConfiguration memory stakeConfiguration = NftStakeContractV1.StakeConfiguration({
            rewardsPerBlock: 2e9,
            tokenId: 0,
            minDelayBetweenRewards: 2 days,
            unbondingPeriod: 3 days,
            minDelayBetweenStakeAndUnstake: 1 days,
            stakeToken: stakeToken,
            nftvault: nftVault
        });

        vm.startBroadcast();
        NftStakeContractV1 nftStakeContractV1 = new NftStakeContractV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftStakeContractV1), "");
        stakeToken.transferOwnership(address(proxy));
        nftVault.transferOwnership(address(proxy));
        NftStakeContractV1(address(proxy)).initialize(stakeConfiguration);
        vm.stopBroadcast();

        return (address(proxy), address(nftStakeContractV1));
    }

    function test() public {}
}
