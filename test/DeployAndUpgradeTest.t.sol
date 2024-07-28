// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployNftStakeContract} from "../script/DeployNftStakeContract.s.sol";
import {UpgradeNftStakeContract} from "../script/UpgradeNftStakeContract.s.sol";
import {NftStakeContractV1} from "../src/NftStakeContractV1.sol";
import {NftStakeContractV2} from "../src/NftStakeContractV2.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {NftVault} from "../src/NftVault.sol";

contract DeployAndUpgradeTest is Test {
    NftVault nftVault;
    StakeToken stakeToken;
    DeployNftStakeContract public deployer;
    UpgradeNftStakeContract public upgrader;
    address public OWNER = makeAddr("owner");

    NftStakeContractV1 public nftStakeContractV1proxy; // contract v1 proxy

    function setUp() public {
        deployer = new DeployNftStakeContract();
        upgrader = new UpgradeNftStakeContract();
        address proxyAddress;
        address nftStakeContractV1Address;
        address nftVaultAddress;
        address stakeTokenAddress;
        (proxyAddress, nftStakeContractV1Address, nftVaultAddress, stakeTokenAddress) = deployer.run();

        nftStakeContractV1proxy = NftStakeContractV1(proxyAddress); // right now , points to v1
        stakeToken = StakeToken(stakeTokenAddress);
        nftVault = NftVault(nftVaultAddress);
    }

    function testUpgrade() public {
        NftStakeContractV2 nftStakeContractV2 = new NftStakeContractV2();
        uint256 initialVersion = nftStakeContractV1proxy.version();
        upgrader.upgradeStakeContract(address(nftStakeContractV1proxy), address(nftStakeContractV2));
        uint256 latestVersion = nftStakeContractV1proxy.version();

        assertEq(initialVersion, 1);
        assertEq(latestVersion, 2);
    }
}
