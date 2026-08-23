// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {TinyAIHolderVault} from "../src/protocol/TinyAIHolderVault.sol";

/// @notice Step 2 of the Token Mode launch: deploy the tax-reward Vault after mining the future Flap CA.
/// @dev This release is deliberately pinned to NVDAB as the Flap quote and holder-reward asset.
contract DeployAIHolderVault is Script {
    uint256 private constant BSC_CHAIN_ID = 56;
    address private constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;

    function run() external {
        require(block.chainid == BSC_CHAIN_ID, "BSC_CHAIN_ID_REQUIRED");
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        address quoteToken = vm.envAddress("FLAP_QUOTE_TOKEN");
        require(quoteToken == NVDAB && quoteToken.code.length > 0, "FLAP_QUOTE_TOKEN_MUST_BE_NVDAB");

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        TinyAIHolderVault holderVault = new TinyAIHolderVault(IERC20(quoteToken), deployer);
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("Flap quote/reward asset", quoteToken);
        console2.log("AI holder reward vault", address(holderVault));
        console2.log("next: predeploy and bind TinyAI to the mined future token CA");
    }
}
