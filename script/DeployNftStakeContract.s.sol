// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; 
import {StakeToken} from "../src/StakeToken.sol";
import {NftVault} from "../src/NftVault.sol";

contract DeployNftStakeContract is Script {


    function run() external returns(address, address, address, address){
        (address proxy, address nftStakeContractV1) = deployNftStakeContract();  
        vm.startBroadcast();
        StakeToken stakeToken = new StakeToken();
        NftVault nftVault = new NftVault(); 
        stakeToken.transferOwnership(nftStakeContractV1);         
        nftVault.transferOwnership(nftStakeContractV1); 
        vm.stopBroadcast();
        return (proxy, nftStakeContractV1, address(nftVault), address(stakeToken)); 
    }

    function deployNftStakeContract() public returns(address, address){
        vm.startBroadcast(); 
        NftStakeContractV1 nftStakeContractV1 = new NftStakeContractV1();
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftStakeContractV1), abi.encodeWithSignature("initialize()")); 
        vm.stopBroadcast();
        return (address(proxy), address(nftStakeContractV1)); 
    }

}