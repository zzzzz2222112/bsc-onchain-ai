// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIGeneratorV6} from "../src/TinyAIGeneratorV6.sol";
import {TinyAIKnowledgeV5} from "../src/TinyAIKnowledgeV5.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIComponents} from "../src/protocol/TinyAIComponents.sol";
import {TinyAIMarket} from "../src/protocol/TinyAIMarket.sol";
import {TinyAIProtocol} from "../src/protocol/TinyAIProtocol.sol";
import {TinyAIV6BrainEngine} from "../src/protocol/TinyAIV6BrainEngine.sol";

/// @notice Deploys a completely new TinyAI stack without reusing any existing contract.
/// @dev This script does nothing on-chain unless Forge is explicitly invoked with --broadcast.
contract DeployFullProtocol is Script {
    uint256 private constant MEMORY_CELL = 1;
    uint256 private constant CURIOSITY_GENE = 2;
    uint256 private constant EMPATHY_GENE = 3;
    uint256 private constant HUMOR_GENE = 4;
    uint256 private constant CAUTION_GENE = 5;
    uint256 private constant EXPRESSION_CORE = 6;

    struct ProtocolStack {
        TinyAIV6BrainEngine brain;
        TinyAIBrainRegistry registry;
        TinyAIComponents components;
        TinyAIProtocol protocol;
        TinyAIMarket market;
    }

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
        address treasury = vm.envAddress("TREASURY");
        string memory componentUri = vm.envOr("COMPONENT_BASE_URI", string("ipfs://tinyai/{id}.json"));

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);

        (TinyAIModelCard model, TinyAIChat classifier) = _deployClassifier();
        TinyAIRetrieverV5 retriever = _deployRetriever(classifier);
        TinyAIGeneratorV6 generator = _deployGenerator(retriever);
        ProtocolStack memory stack = _deployProtocol(generator, deployer, finalOwner, treasury, componentUri);

        vm.stopBroadcast();

        console2.log("deployer / protocol owner", deployer);
        console2.log("treasury", treasury);
        console2.log("model card", address(model));
        console2.log("v3 classifier", address(classifier));
        console2.log("v5 retriever", address(retriever));
        console2.log("v6 generator", address(generator));
        console2.log("genesis brain", address(stack.brain));
        console2.log("brain registry", address(stack.registry));
        console2.log("components", address(stack.components));
        console2.log("AI protocol", address(stack.protocol));
        console2.log("market", address(stack.market));
    }

    function _deployClassifier() private returns (TinyAIModelCard model, TinyAIChat classifier) {
        address[22] memory weightsBlobs;
        for (uint256 index; index < weightsBlobs.length; ++index) {
            bytes memory weightChunk =
                vm.readFileBinary(string.concat("../model/build/model-", vm.toString(index), ".bin"));
            weightsBlobs[index] = address(new BytecodeBlob(weightChunk));
        }

        address zhLexiconBlob = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-zh.bin")));
        address enLexiconBlob = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-en.bin")));
        bytes32 corpusSha256 = vm.parseBytes32(string.concat("0x", _trim(vm.readFile("../model/build/corpus.sha256"))));

        model = new TinyAIModelCard(weightsBlobs, zhLexiconBlob, enLexiconBlob, corpusSha256);
        classifier = new TinyAIChat(model, IERC20(address(0)), address(0), 0, 0);
    }

    function _deployRetriever(TinyAIChat classifier) private returns (TinyAIRetrieverV5 retriever) {
        TinyAIKnowledgeV5 knowledge = new TinyAIKnowledgeV5();
        retriever = new TinyAIRetrieverV5(classifier, knowledge);
    }

    function _deployGenerator(TinyAIRetrieverV5 retriever) private returns (TinyAIGeneratorV6 generator) {
        BytecodeBlob modelBlob = new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-model.bin"));
        BytecodeBlob lexiconBlob = new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-lexicon.bin"));
        generator = new TinyAIGeneratorV6(retriever, address(modelBlob), address(lexiconBlob));
    }

    function _deployProtocol(
        TinyAIGeneratorV6 generator,
        address deployer,
        address finalOwner,
        address treasury,
        string memory componentUri
    ) private returns (ProtocolStack memory stack) {
        stack.brain = new TinyAIV6BrainEngine(generator);
        stack.registry = new TinyAIBrainRegistry(deployer);
        stack.registry.publish(address(stack.brain), "Genesis Brain V1 / TinyAI v6", true);
        stack.components = new TinyAIComponents(componentUri, deployer, treasury);
        stack.protocol = new TinyAIProtocol(stack.registry, stack.components, deployer, treasury);
        stack.components.bindProtocol(address(stack.protocol));
        stack.market = new TinyAIMarket(address(stack.protocol), address(stack.components));

        _defineGenesisComponents(stack.components);
        stack.components.sealCatalog();

        if (finalOwner != deployer) {
            stack.registry.transferOwnership(finalOwner);
            stack.components.transferOwnership(finalOwner);
            stack.protocol.transferOwnership(finalOwner);
        }
    }

    function _defineGenesisComponents(TinyAIComponents components) private {
        components.defineComponent(MEMORY_CELL, components.EFFECT_MEMORY(), 0, 1, 30_000);
        components.defineComponent(CURIOSITY_GENE, components.EFFECT_PERSONALITY(), 0, 5, 15_000);
        components.defineComponent(EMPATHY_GENE, components.EFFECT_PERSONALITY(), 1, 5, 15_000);
        components.defineComponent(HUMOR_GENE, components.EFFECT_PERSONALITY(), 2, 5, 15_000);
        components.defineComponent(CAUTION_GENE, components.EFFECT_PERSONALITY(), 3, 5, 15_000);
        components.defineComponent(EXPRESSION_CORE, components.EFFECT_EXPRESSION(), 0, 1, 10_000);
    }

    function _trim(string memory value) private pure returns (string memory) {
        bytes memory raw = bytes(value);
        uint256 length = raw.length;
        while (length != 0 && (raw[length - 1] == 0x0A || raw[length - 1] == 0x0D || raw[length - 1] == 0x20)) {
            length -= 1;
        }
        bytes memory output = new bytes(length);
        for (uint256 index; index < length; ++index) {
            output[index] = raw[index];
        }
        return string(output);
    }
}
