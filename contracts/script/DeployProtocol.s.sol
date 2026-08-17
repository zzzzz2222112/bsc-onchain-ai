// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {TinyAIGeneratorV6} from "../src/TinyAIGeneratorV6.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIComponents} from "../src/protocol/TinyAIComponents.sol";
import {TinyAIMarket} from "../src/protocol/TinyAIMarket.sol";
import {TinyAIProtocol} from "../src/protocol/TinyAIProtocol.sol";
import {TinyAIV6BrainEngine} from "../src/protocol/TinyAIV6BrainEngine.sol";

/// @notice Deploys the protocol layer around an existing immutable TinyAI v6 generator.
/// @dev This script does nothing on-chain unless Forge is explicitly invoked with --broadcast.
contract DeployProtocol is Script {
    uint256 private constant MEMORY_CELL = 1;
    uint256 private constant CURIOSITY_GENE = 2;
    uint256 private constant EMPATHY_GENE = 3;
    uint256 private constant HUMOR_GENE = 4;
    uint256 private constant CAUTION_GENE = 5;
    uint256 private constant EXPRESSION_CORE = 6;

    function run() external {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        address finalOwner = vm.envOr("PROTOCOL_OWNER", deployer);
        address treasury = vm.envOr("TREASURY", finalOwner);
        string memory componentUri = vm.envOr("COMPONENT_BASE_URI", string("ipfs://tinyai/{id}.json"));
        TinyAIGeneratorV6 generator = TinyAIGeneratorV6(vm.envAddress("GENERATOR_V6"));

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        TinyAIV6BrainEngine brain = new TinyAIV6BrainEngine(generator);
        TinyAIBrainRegistry registry = new TinyAIBrainRegistry(deployer);
        registry.publish(address(brain), "Genesis Brain V1 / TinyAI v6", true);
        TinyAIComponents components = new TinyAIComponents(componentUri, deployer, treasury);
        TinyAIProtocol protocol = new TinyAIProtocol(registry, components, deployer, treasury);
        components.bindProtocol(address(protocol));
        TinyAIMarket market = new TinyAIMarket(address(protocol), address(components));

        _defineGenesisComponents(components);
        components.sealCatalog();

        if (finalOwner != deployer) {
            registry.transferOwnership(finalOwner);
            components.transferOwnership(finalOwner);
            protocol.transferOwnership(finalOwner);
        }
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("pending/final owner", finalOwner);
        console2.log("treasury", treasury);
        console2.log("v6 generator", address(generator));
        console2.log("genesis brain", address(brain));
        console2.log("brain registry", address(registry));
        console2.log("components", address(components));
        console2.log("AI protocol", address(protocol));
        console2.log("market", address(market));
        console2.log("AI mint price", protocol.MINT_PRICE());
        console2.log("market fee bps", market.MARKET_FEE_BPS());
    }

    function _defineGenesisComponents(TinyAIComponents components) private {
        components.defineComponent(MEMORY_CELL, components.EFFECT_MEMORY(), 0, 1, 30_000);
        components.defineComponent(CURIOSITY_GENE, components.EFFECT_PERSONALITY(), 0, 5, 15_000);
        components.defineComponent(EMPATHY_GENE, components.EFFECT_PERSONALITY(), 1, 5, 15_000);
        components.defineComponent(HUMOR_GENE, components.EFFECT_PERSONALITY(), 2, 5, 15_000);
        components.defineComponent(CAUTION_GENE, components.EFFECT_PERSONALITY(), 3, 5, 15_000);
        components.defineComponent(EXPRESSION_CORE, components.EFFECT_EXPRESSION(), 0, 1, 10_000);
    }
}
