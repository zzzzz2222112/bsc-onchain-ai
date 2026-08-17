// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIGeneratorV6} from "../src/TinyAIGeneratorV6.sol";
import {TinyAIKnowledgeV5} from "../src/TinyAIKnowledgeV5.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";
import {IBrainEngine} from "../src/protocol/IBrainEngine.sol";
import {TinyAIBrainEngineV2} from "../src/protocol/TinyAIBrainEngineV2.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIComponents} from "../src/protocol/TinyAIComponents.sol";
import {TinyAINeuralDecoderV2} from "../src/protocol/TinyAINeuralDecoderV2.sol";
import {TinyAIProtocol} from "../src/protocol/TinyAIProtocol.sol";
import {TinyAIV6BrainEngine} from "../src/protocol/TinyAIV6BrainEngine.sol";

contract TinyAIBrainEngineV2Test is Test {
    bytes32 private constant V3_CORPUS_SHA256 = 0x9bd76b2daefa3ac5a59852e3f8fa2e46bae52846b26b884918ac82f0b3cac8e7;
    uint256 private constant BSC_TRANSACTION_GAS_LIMIT = 16_777_216;

    address private alice = makeAddr("alice");
    TinyAIRetrieverV5 private retriever;
    TinyAIGeneratorV6 private legacyGenerator;
    TinyAINeuralDecoderV2 private decoder;
    TinyAIV6BrainEngine private brainV1;
    TinyAIBrainEngineV2 private brainV2;

    function setUp() public {
        address[22] memory weights;
        for (uint256 index; index < weights.length; ++index) {
            weights[index] = address(
                new BytecodeBlob(vm.readFileBinary(string.concat("../model/build/model-", vm.toString(index), ".bin")))
            );
        }
        address zh = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-zh.bin")));
        address en = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-en.bin")));
        TinyAIModelCard model = new TinyAIModelCard(weights, zh, en, V3_CORPUS_SHA256);
        TinyAIChat classifier = new TinyAIChat(model, IERC20(address(0)), address(0), 0, 0);
        retriever = new TinyAIRetrieverV5(classifier, new TinyAIKnowledgeV5());

        address generatorModel = address(new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-model.bin")));
        address generatorLexicon =
            address(new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-lexicon.bin")));
        legacyGenerator = new TinyAIGeneratorV6(retriever, generatorModel, generatorLexicon);
        decoder = new TinyAINeuralDecoderV2(generatorModel, generatorLexicon);
        brainV1 = new TinyAIV6BrainEngine(legacyGenerator);
        brainV2 = new TinyAIBrainEngineV2(retriever, decoder);
    }

    function testAllTwentyFourNeuralOutputsAreByteExact() public view {
        for (uint8 context; context < 6; ++context) {
            for (uint8 variant; variant < 4; ++variant) {
                TinyAIGeneratorV6.NeuralOutput memory legacy = legacyGenerator.generateFromContext(context, variant);
                TinyAINeuralDecoderV2.NeuralOutput memory optimized = decoder.generateFromContext(context, variant);

                assertEq(optimized.response, legacy.response, "response mismatch");
                assertEq(optimized.context, legacy.context, "context mismatch");
                assertEq(optimized.variant, legacy.variant, "variant mismatch");
                assertEq(optimized.tokenCount, legacy.tokenCount, "token count mismatch");
                assertEq(optimized.stepCount, legacy.stepCount, "step count mismatch");
                assertEq(optimized.traceHash, legacy.traceHash, "trace mismatch");
                for (uint256 index; index < 16; ++index) {
                    assertEq(optimized.tokenIds[index], legacy.tokenIds[index], "token mismatch");
                    assertEq(optimized.tokenScores[index], legacy.tokenScores[index], "score mismatch");
                }
            }
        }
    }

    function testBrainV2MatchesV1ObservableAnswer() public view {
        IBrainEngine.BrainInput memory input = _input(unicode"你知道什么是 BSC 吗？");
        IBrainEngine.BrainOutput memory legacy = brainV1.infer(input);
        IBrainEngine.BrainOutput memory optimized = brainV2.infer(input);

        assertEq(optimized.response, legacy.response);
        assertEq(optimized.confidence, legacy.confidence);
        assertEq(optimized.topic, legacy.topic);
        assertEq(optimized.variant, legacy.variant);
        assertEq(optimized.unknown, legacy.unknown);
        assertEq(optimized.neuralGenerated, legacy.neuralGenerated);
        assertNotEq(optimized.traceHash, legacy.traceHash, "versioned engine trace should change");
    }

    function testUnknownQuestionStillRefusesPolitely() public view {
        IBrainEngine.BrainOutput memory output = brainV2.infer(_input(unicode"恐龙为什么灭绝？"));
        assertTrue(output.unknown);
        assertFalse(output.neuralGenerated);
        assertEq(output.variant, 0);
        assertGt(bytes(output.response).length, 0);
    }

    function testBrainV2FitsBscTransactionGasLimit() public {
        IBrainEngine.BrainInput memory input = _input(unicode"你知道什么是 BSC 吗？");
        uint256 beforeGas = gasleft();
        IBrainEngine.BrainOutput memory output = brainV2.infer(input);
        uint256 used = beforeGas - gasleft();

        assertTrue(output.neuralGenerated);
        emit log_named_uint("brain v2 neural inference gas", used);
        assertLt(used, BSC_TRANSACTION_GAS_LIMIT, "Brain V2 exceeds BSC per-transaction gas limit");
    }

    function testEverySupportedNeuralRouteFitsBscTransactionGasLimit() public {
        string[6] memory prompts = [
            unicode"你是什么？",
            unicode"BSC 是什么？",
            unicode"你知道什么是人类吗？",
            unicode"把 Gas 提高十倍，AI 会聪明十倍吗？",
            unicode"这个合约可以增发，而且管理员还在，安全吗？",
            unicode"这是代理合约，管理员能升级，有什么风险？"
        ];
        uint256 highestGas;
        for (uint256 index; index < prompts.length; ++index) {
            uint256 beforeGas = gasleft();
            IBrainEngine.BrainOutput memory output = brainV2.infer(_input(prompts[index]));
            uint256 used = beforeGas - gasleft();
            if (used > highestGas) highestGas = used;
            assertTrue(output.neuralGenerated, "supported route did not use neural decoder");
            assertLt(used, BSC_TRANSACTION_GAS_LIMIT, "supported route exceeds BSC transaction gas limit");
        }
        emit log_named_uint("highest supported Brain V2 inference gas", highestGas);
    }

    function testRegistryUpgradeAndFullProtocolChatFitBscLimit() public {
        TinyAIBrainRegistry registry = new TinyAIBrainRegistry(address(this));
        registry.publish(address(brainV1), "Genesis Brain V1", true);
        TinyAIComponents components = new TinyAIComponents("ipfs://tinyai/{id}.json", address(this), address(0xBEEF));
        TinyAIProtocol protocol = new TinyAIProtocol(registry, components, address(this), address(0xBEEF));
        components.bindProtocol(address(protocol));
        vm.deal(alice, 1 ether);

        uint256 mintPrice = protocol.MINT_PRICE();
        vm.prank(alice);
        uint256 aiId = protocol.mintAI{value: mintPrice}("MOMO", bytes32("v2-upgrade"), true);
        registry.publish(address(brainV2), "Gas-Bounded Brain V2", true);

        uint256 beforeGas = gasleft();
        vm.prank(alice);
        IBrainEngine.BrainOutput memory output = protocol.chatAI(aiId, unicode"你知道什么是 BSC 吗？");
        uint256 used = beforeGas - gasleft();

        TinyAIProtocol.AIState memory state = protocol.aiState(aiId);
        assertTrue(output.neuralGenerated);
        assertEq(state.brainVersion, 2);
        assertEq(state.turns, 1);
        assertEq(state.experience, 3);
        assertNotEq(state.memoryRoot, bytes32(0));
        assertNotEq(protocol.memoryAt(aiId, 0), bytes32(0));
        emit log_named_uint("full protocol auto-upgrade plus chat gas", used);
        assertLt(used, BSC_TRANSACTION_GAS_LIMIT, "full protocol chat exceeds BSC transaction gas limit");
    }

    function testOnlyRegistryOwnerCanPublishBrainV2() public {
        TinyAIBrainRegistry registry = new TinyAIBrainRegistry(address(this));
        registry.publish(address(brainV1), "Genesis Brain V1", true);
        address stranger = makeAddr("stranger");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", stranger));
        registry.publish(address(brainV2), "Gas-Bounded Brain V2", true);

        assertEq(registry.latestVersion(), 1);
        assertEq(registry.recommendedVersion(), 1);
    }

    function testVersionAndIntegrityAreLocked() public view {
        assertEq(brainV2.engineVersion(), 2);
        assertEq(decoder.VERSION(), 2);
        assertEq(decoder.MODEL_VERSION(), 6);
        assertTrue(decoder.integrityOk());
        assertTrue(brainV2.integrityOk());
        assertLt(address(decoder).code.length, 24_576);
        assertLt(address(brainV2).code.length, 24_576);
    }

    function _input(string memory prompt) private view returns (IBrainEngine.BrainInput memory) {
        return IBrainEngine.BrainInput({
            aiId: 42,
            dna: keccak256("momo"),
            curiosity: 80,
            empathy: 61,
            humor: 44,
            caution: 73,
            expressionLevel: 2,
            skillMask: 0,
            turns: 3,
            memoryRoot: keccak256("memory"),
            speaker: alice,
            prompt: prompt
        });
    }
}
