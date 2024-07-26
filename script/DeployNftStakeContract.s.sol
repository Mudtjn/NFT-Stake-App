// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; 


contract DeployNftStakeContract is Script {

    function run() external returns(address proxy){
        proxy = deployNftStakeContract();  
    }

    function deployNftStakeContract() public returns(address){
        vm.startBroadcast(); 
        NftStakeContractV1 nftStakeContractV1 = new NftStakeContractV1(); 
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftStakeContractV1), ""); 
        vm.stopBroadcast();
        return address(proxy); 
    }
}