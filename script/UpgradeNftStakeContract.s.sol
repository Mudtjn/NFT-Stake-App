// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20; 

import {Script} from "forge-std/Script.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {DevOpsTools} from "foundry-devops/DevOpsTools.sol"; 

contract UpgradeNftStakeContract is Script {
    function run() external returns(address){
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);
    
        vm.startBroadcast();
        // nftStakeContractV2 deployment
        vm.stopBroadcast(); 
        address proxy = upgradeBox(mostRecentlyDeployed, address(1));
        return proxy;  
    }    

    function upgradeBox(address proxyAddress, address newContract) public returns(address) {
        vm.startBroadcast(); 
        NftStakeContractV1 proxy = NftStakeContractV1(proxyAddress); 
        proxy.upgradeToAndCall(address(newContract),""); 
        vm.stopBroadcast(); 
        return address(proxy); 
    }

    
}