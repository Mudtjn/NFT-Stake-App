// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/DevOpsTools.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {NftStakeContractV2} from "../src/NftStakeContractV2.sol";
/**
 * This is an example upgrade script
 * So I am updating the state to another instance of contract NftStakeContractV1
 */

contract UpgradeNftStakeContract is Script {
    function run() external returns (address) {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);
        vm.startBroadcast();
        NftStakeContractV2 newStakeContract = new NftStakeContractV2();
        vm.stopBroadcast();
        address proxy = upgradeStakeContract(mostRecentlyDeployed, address(newStakeContract));
    }

    function upgradeStakeContract(address proxyAddress, address newStakeContract) public returns (address) {
        vm.startBroadcast();
        NftStakeContractV1 proxy = NftStakeContractV1(proxyAddress);
        proxy.pauseContract();
        proxy.upgradeToAndCall(newStakeContract, "");
        vm.stopBroadcast();
        return address(proxy);
    }

    function test() public {}
}
