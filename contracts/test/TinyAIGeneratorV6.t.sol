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
import {TinyAIV6BrainEngine} from "../src/protocol/TinyAIV6BrainEngine.sol";

contract TinyAIGeneratorV6Test is Test {
    bytes32 private constant V3_CORPUS_SHA256 = 0x9bd76b2daefa3ac5a59852e3f8fa2e46bae52846b26b884918ac82f0b3cac8e7;

    address private alice = makeAddr("alice");
    TinyAIChat private classifier;
    TinyAIKnowledgeV5 private knowledge;
    TinyAIRetrieverV5 private retriever;
    BytecodeBlob private generatorModel;
    BytecodeBlob private generatorLexicon;
    TinyAIGeneratorV6 private generator;
    TinyAIV6BrainEngine private protocolBrain;

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
        classifier = new TinyAIChat(model, IERC20(address(0)), address(0), 0, 0);
        knowledge = new TinyAIKnowledgeV5();
        retriever = new TinyAIRetrieverV5(classifier, knowledge);

        generatorModel = new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-model.bin"));
        generatorLexicon = new BytecodeBlob(vm.readFileBinary("../model/build/generator-v6-lexicon.bin"));
        generator = new TinyAIGeneratorV6(retriever, address(generatorModel), address(generatorLexicon));
        protocolBrain = new TinyAIV6BrainEngine(generator);
    }

    function testLocksCanonicalModulesAndFitsRuntimeLimit() public view {
        assertEq(generator.VERSION(), 6);
        assertEq(address(generator.retriever()), address(retriever));
        assertEq(generator.modelBlob(), address(generatorModel));
        assertEq(generator.lexiconBlob(), address(generatorLexicon));
        assertEq(generator.retrieverCodeHash(), address(retriever).codehash);
        assertEq(generator.modelCodeHash(), address(generatorModel).codehash);
        assertEq(generator.lexiconCodeHash(), address(generatorLexicon).codehash);
        assertEq(generator.MODEL_SHA256(), sha256(vm.readFileBinary("../model/build/generator-v6-model.bin")));
        assertEq(generator.LEXICON_SHA256(), sha256(vm.readFileBinary("../model/build/generator-v6-lexicon.bin")));
        assertTrue(generator.integrityOk());
        assertLt(address(generator).code.length, 24_576);
    }

    function testAllTwentyFourPythonVectorsMatchSolidityTokensScoresAndText() public view {
        string memory vectors = vm.readFile("../model/build/generator-v6-vectors.json");
        for (uint256 index; index < 24; ++index) {
            string memory root = string.concat("$[", vm.toString(index), "]");
            string memory expectedResponse = vm.parseJsonString(vectors, string.concat(root, ".response"));
            uint256[] memory expectedIds =
                abi.decode(vm.parseJson(vectors, string.concat(root, ".tokenIds")), (uint256[]));
            int256[] memory expectedScores =
                abi.decode(vm.parseJson(vectors, string.concat(root, ".scores")), (int256[]));

            TinyAIGeneratorV6.NeuralOutput memory output =
                generator.generateFromContext(uint8(index / 4), uint8(index % 4));
            assertEq(output.response, expectedResponse, string.concat("response vector ", vm.toString(index)));
            assertEq(output.tokenCount, expectedIds.length, string.concat("token count vector ", vm.toString(index)));
            assertEq(output.stepCount, expectedScores.length, string.concat("step count vector ", vm.toString(index)));
            for (uint256 tokenIndex; tokenIndex < expectedIds.length; ++tokenIndex) {
                assertEq(output.tokenIds[tokenIndex], expectedIds[tokenIndex], "token id mismatch");
            }
            for (uint256 stepIndex; stepIndex < expectedScores.length; ++stepIndex) {
                assertEq(output.tokenScores[stepIndex], expectedScores[stepIndex], "token score mismatch");
            }
            assertNotEq(output.traceHash, bytes32(0));
        }
    }

    function testBscQuestionUsesNeuralGenerationAndGrounding() public view {
        TinyAIGeneratorV6.GenerationResult memory result =
            generator.preview(alice, unicode"你知道什么是 BSC 吗？");

        assertTrue(result.neuralGenerated);
        assertEq(result.neuralContext, generator.CONTEXT_BSC());
        assertEq(result.factIds[0], 1301);
        assertGt(result.tokenCount, 0);
        assertEq(result.stepCount, result.tokenCount + 1);
        assertTrue(_contains(result.response, "BSC") || _contains(result.response, "BNB Smart Chain"));
        assertNotEq(result.retrievalTraceHash, bytes32(0));
        assertNotEq(result.generationTraceHash, bytes32(0));
    }

    function testEverySupportedContextRoutesToNeuralGenerator() public view {
        string[6] memory prompts = [
            unicode"你是什么？",
            unicode"BSC 是什么？",
            unicode"你知道什么是人类吗？",
            unicode"把 Gas 提高十倍，AI 会聪明十倍吗？",
            unicode"这个合约可以增发，而且管理员还在，安全吗？",
            unicode"这是代理合约，管理员能升级，有什么风险？"
        ];
        for (uint256 index; index < prompts.length; ++index) {
            TinyAIGeneratorV6.GenerationResult memory result = generator.preview(alice, prompts[index]);
            assertTrue(result.neuralGenerated, string.concat("route ", vm.toString(index)));
            assertEq(result.neuralContext, index);
            assertGt(result.tokenCount, 0);
        }
    }

    function testUnknownEnglishAndNegatedRiskUseSafeV5Fallback() public view {
        string[3] memory prompts = [
            unicode"恐龙为什么灭绝？",
            "What is BSC?",
            unicode"这个合约不能增发，管理员还在，安全吗？"
        ];
        for (uint256 index; index < prompts.length; ++index) {
            TinyAIGeneratorV6.GenerationResult memory result = generator.preview(alice, prompts[index]);
            assertFalse(result.neuralGenerated);
            assertEq(result.neuralContext, generator.NO_NEURAL_CONTEXT());
            assertEq(result.tokenCount, 0);
            assertNotEq(result.response, "");
        }
        assertTrue(generator.preview(alice, prompts[0]).unknown);
        assertTrue(generator.preview(alice, prompts[2]).negated);
    }

    function testGenerationIsDeterministic() public view {
        string memory prompt = unicode"BSC 为什么使用 Gas？";
        TinyAIGeneratorV6.GenerationResult memory first = generator.preview(alice, prompt);
        TinyAIGeneratorV6.GenerationResult memory second = generator.preview(alice, prompt);
        assertEq(first.response, second.response);
        assertEq(first.generationTraceHash, second.generationTraceHash);
        assertEq(keccak256(abi.encode(first.tokenIds)), keccak256(abi.encode(second.tokenIds)));
        assertEq(keccak256(abi.encode(first.tokenScores)), keccak256(abi.encode(second.tokenScores)));
    }

    function testGenesisProtocolBrainUsesRealV6AndAIDna() public view {
        IBrainEngine.BrainInput memory input = IBrainEngine.BrainInput({
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
            prompt: unicode"你知道什么是 BSC 吗？"
        });
        IBrainEngine.BrainOutput memory output = protocolBrain.infer(input);

        assertEq(protocolBrain.engineVersion(), 1);
        assertTrue(protocolBrain.integrityOk());
        assertTrue(output.neuralGenerated);
        assertFalse(output.unknown);
        assertEq(output.topic, 3);
        assertLt(output.variant, 4);
        assertGt(bytes(output.response).length, 0);
        assertNotEq(output.traceHash, bytes32(0));
    }

    function testGenesisProtocolBrainPreservesV5UnknownRefusal() public view {
        IBrainEngine.BrainInput memory input = IBrainEngine.BrainInput({
            aiId: 1,
            dna: keccak256("nana"),
            curiosity: 50,
            empathy: 50,
            humor: 50,
            caution: 50,
            expressionLevel: 0,
            skillMask: 0,
            turns: 0,
            memoryRoot: bytes32(0),
            speaker: alice,
            prompt: unicode"恐龙为什么灭绝？"
        });
        IBrainEngine.BrainOutput memory output = protocolBrain.infer(input);

        assertTrue(output.unknown);
        assertFalse(output.neuralGenerated);
        assertEq(output.variant, 0);
        assertGt(bytes(output.response).length, 0);
    }

    function testChatPersistsAuditableMemory() public {
        vm.prank(alice);
        TinyAIGeneratorV6.GenerationResult memory result = generator.chat(unicode"什么是 BSC？");
        TinyAIGeneratorV6.Memory memory remembered = generator.memoryOf(alice);

        assertEq(generator.totalChats(), 1);
        assertEq(remembered.turns, 1);
        assertEq(remembered.lastTopic, result.topic);
        assertEq(remembered.lastNeuralContext, result.neuralContext);
        assertEq(remembered.lastTokenCount, result.tokenCount);
        assertEq(remembered.rollingContext, result.nextContext);
    }

    function testRejectsInvalidContextVariantAndModules() public {
        vm.expectRevert(abi.encodeWithSelector(TinyAIGeneratorV6.InvalidNeuralContext.selector, 6));
        generator.generateFromContext(6, 0);
        vm.expectRevert(abi.encodeWithSelector(TinyAIGeneratorV6.InvalidVariant.selector, 4));
        generator.generateFromContext(0, 4);

        vm.expectRevert(TinyAIGeneratorV6.InvalidRetriever.selector);
        new TinyAIGeneratorV6(TinyAIRetrieverV5(address(0)), address(generatorModel), address(generatorLexicon));
        vm.expectRevert(TinyAIGeneratorV6.InvalidModel.selector);
        new TinyAIGeneratorV6(retriever, address(generatorLexicon), address(generatorLexicon));
        vm.expectRevert(TinyAIGeneratorV6.InvalidLexicon.selector);
        new TinyAIGeneratorV6(retriever, address(generatorModel), address(generatorModel));
    }

    function testMeasureNeuralPreviewGas() public {
        uint256 beforeGas = gasleft();
        TinyAIGeneratorV6.GenerationResult memory result =
            generator.preview(alice, unicode"你知道什么是 BSC 吗？");
        uint256 used = beforeGas - gasleft();

        assertTrue(result.neuralGenerated);
        emit log_named_uint("v6 BSC neural preview gas", used);
        assertLt(used, 55_000_000, "v6 neural generation exceeds the local block gas limit");
    }

    function testMeasureGasBreakdown() public {
        string memory prompt = unicode"你知道什么是 BSC 吗？";
        uint256 beforeGas = gasleft();
        TinyAIChat.InferenceResult memory classification = classifier.preview(alice, prompt);
        uint256 classifierGas = beforeGas - gasleft();

        beforeGas = gasleft();
        TinyAIRetrieverV5.RetrievalResult memory retrieval = retriever.preview(alice, prompt);
        uint256 retrieverGas = beforeGas - gasleft();

        beforeGas = gasleft();
        TinyAIGeneratorV6.NeuralOutput memory generation = generator.generateFromContext(generator.CONTEXT_BSC(), 0);
        uint256 generatorGas = beforeGas - gasleft();

        IBrainEngine.BrainInput memory input = IBrainEngine.BrainInput({
            aiId: 42,
            dna: keccak256("gas-breakdown"),
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
        beforeGas = gasleft();
        IBrainEngine.BrainOutput memory output = protocolBrain.infer(input);
        uint256 brainGas = beforeGas - gasleft();

        assertGt(classification.confidence, 0);
        assertGt(retrieval.classifierConfidence, 0);
        assertGt(generation.tokenCount, 0);
        assertTrue(output.neuralGenerated);
        emit log_named_uint("v3 classifier gas", classifierGas);
        emit log_named_uint("v5 retriever gas", retrieverGas);
        emit log_named_uint("v6 generator-only gas", generatorGas);
        emit log_named_uint("v1 protocol brain gas", brainGas);
    }

    function _contains(string memory haystack, string memory needle) private pure returns (bool) {
        bytes memory source = bytes(haystack);
        bytes memory target = bytes(needle);
        if (target.length == 0 || target.length > source.length) return false;
        for (uint256 start; start + target.length <= source.length; ++start) {
            bool same = true;
            for (uint256 index; index < target.length; ++index) {
                if (source[start + index] != target[index]) {
                    same = false;
                    break;
                }
            }
            if (same) return true;
        }
        return false;
    }
}
