// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {TinyAIGeneratorV6} from "../src/TinyAIGeneratorV6.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";
import {IBrainEngine} from "../src/protocol/IBrainEngine.sol";
import {TinyAIBrainEngineV2} from "../src/protocol/TinyAIBrainEngineV2.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAINeuralDecoderV2} from "../src/protocol/TinyAINeuralDecoderV2.sol";

/// @notice Adds gas-bounded Brain V2 to an existing TinyAI Genesis protocol.
/// @dev Reuses the immutable v5 retriever and v6 model/lexicon blobs. Nothing is
///      submitted unless Forge is explicitly invoked with --broadcast.
contract UpgradeBrainV2 is Script {
    error InvalidGenesisGenerator();
    error UnexpectedRegistryVersion(uint32 current);
    error RegistryOwnerMismatch(address expected, address actual);
    error UpgradeVerificationFailed();

    function run() external returns (TinyAINeuralDecoderV2 decoder, TinyAIBrainEngineV2 brain) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        TinyAIGeneratorV6 generator = TinyAIGeneratorV6(vm.envAddress("GENERATOR_V6"));
        TinyAIBrainRegistry registry = TinyAIBrainRegistry(vm.envAddress("BRAIN_REGISTRY"));
        bool makeRecommended = vm.envOr("MAKE_RECOMMENDED", true);

        if (address(generator).code.length == 0 || !generator.integrityOk()) revert InvalidGenesisGenerator();
        uint32 latest = registry.latestVersion();
        if (latest != 1) revert UnexpectedRegistryVersion(latest);
        address registryOwner = registry.owner();
        if (registryOwner != deployer) revert RegistryOwnerMismatch(deployer, registryOwner);

        TinyAIRetrieverV5 retriever = generator.retriever();
        address modelBlob = generator.modelBlob();
        address lexiconBlob = generator.lexiconBlob();

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        decoder = new TinyAINeuralDecoderV2(modelBlob, lexiconBlob);
        brain = new TinyAIBrainEngineV2(retriever, decoder);
        uint32 publishedVersion = registry.publish(address(brain), "Gas-Bounded Brain V2 / TinyAI v6", makeRecommended);
        vm.stopBroadcast();

        if (
            publishedVersion != 2 || registry.latestVersion() != 2 || address(registry.engineFor(2)) != address(brain)
                || !brain.integrityOk()
        ) revert UpgradeVerificationFailed();
        if (makeRecommended && registry.recommendedVersion() != 2) revert UpgradeVerificationFailed();

        console2.log("deployer / registry owner", deployer);
        console2.log("brain registry", address(registry));
        console2.log("reused v5 retriever", address(retriever));
        console2.log("reused v6 model blob", modelBlob);
        console2.log("reused v6 lexicon blob", lexiconBlob);
        console2.log("neural decoder v2", address(decoder));
        console2.log("brain v2", address(brain));
        console2.log("recommended", makeRecommended);
    }
}
