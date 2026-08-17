// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIKnowledgeV5} from "../src/TinyAIKnowledgeV5.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";

contract TinyAIRetrieverV5Test is Test {
    bytes32 private constant CORPUS_SHA256 = 0x9bd76b2daefa3ac5a59852e3f8fa2e46bae52846b26b884918ac82f0b3cac8e7;

    address private alice = makeAddr("alice");
    TinyAIModelCard private model;
    TinyAIChat private classifier;
    TinyAIKnowledgeV5 private knowledge;
    TinyAIRetrieverV5 private retriever;

    function setUp() public {
        address[22] memory weights;
        for (uint256 index; index < weights.length; ++index) {
            weights[index] = address(
                new BytecodeBlob(vm.readFileBinary(string.concat("../model/build/model-", vm.toString(index), ".bin")))
            );
        }
        address zh = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-zh.bin")));
        address en = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-en.bin")));
        model = new TinyAIModelCard(weights, zh, en, CORPUS_SHA256);
        classifier = new TinyAIChat(model, IERC20(address(0)), address(0), 0, 0);
        knowledge = new TinyAIKnowledgeV5();
        retriever = new TinyAIRetrieverV5(classifier, knowledge);
    }

    function testReusesTrainedClassifierAndLocksEveryModule() public view {
        assertEq(retriever.VERSION(), 5);
        assertEq(address(retriever.classifier()), address(classifier));
        assertEq(address(retriever.modelCard()), address(model));
        assertEq(address(retriever.knowledge()), address(knowledge));
        assertEq(retriever.KNOWLEDGE_HASH(), knowledge.KNOWLEDGE_HASH());
        assertEq(retriever.classifierCodeHash(), address(classifier).codehash);
        assertEq(retriever.modelCardCodeHash(), address(model).codehash);
        assertEq(retriever.knowledgeCodeHash(), address(knowledge).codehash);
        assertTrue(retriever.integrityOk());
        assertLt(address(retriever).code.length, 24_576);
        assertLt(address(knowledge).code.length, 24_576);
    }

    function testBscQuestionRetrievesThreeSpecificFacts() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"你知道什么是 BSC 吗？");

        assertEq(result.topic, retriever.TOPIC_BSC());
        assertEq(result.factCount, 3);
        assertEq(result.factIds[0], 1301);
        assertFalse(result.unknown);
        assertTrue(_contains(result.response, "BNB Smart Chain"));
        assertTrue(_contains(result.response, unicode"BNB 支付 Gas"));
        assertTrue(_contains(result.evidence, "[1303]"));
    }

    function testHumanQuestionNoLongerFallsBackToIdentity() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"你知道什么是人类吗？");

        assertEq(result.topic, retriever.TOPIC_HUMAN());
        assertEq(result.factIds[0], 1401);
        assertTrue(_contains(result.response, unicode"智人"));
        assertTrue(_contains(result.response, unicode"语言、合作、制度和文化"));
        assertFalse(_contains(result.response, unicode"电子宠物"));
    }

    function testGasAndAiQuestionUsesRelevantThirdFact() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"把 Gas 提高十倍，AI 会聪明十倍吗？");

        assertEq(result.topic, retriever.TOPIC_GAS());
        assertEq(result.factIds[2], 1503);
        assertTrue((result.cues & retriever.CUE_AI()) != 0);
        assertTrue((result.cues & retriever.CUE_SCALE()) != 0);
        assertTrue(_contains(result.response, unicode"原算法不变不会自动变聪明"));
    }

    function testUnknownQuestionsDeclinePolitelyInsteadOfInventing() public view {
        string[3] memory prompts = [
            unicode"恐龙为什么灭绝？", unicode"怎么做红烧肉？", unicode"量子香蕉今晚做梦吗？"
        ];

        for (uint256 index; index < prompts.length; ++index) {
            TinyAIRetrieverV5.RetrievalResult memory result = retriever.preview(alice, prompts[index]);
            assertEq(result.topic, retriever.TOPIC_UNKNOWN());
            assertEq(result.factCount, 0);
            assertTrue(result.unknown);
            assertTrue(_contains(result.response, unicode"这个问题挺有意思"));
            assertTrue(_contains(result.response, unicode"为了不误导你"));
            assertFalse(_contains(result.response, unicode"低置信度推测"));
        }
    }

    function testMintAdminCombinationProducesSupplyRisk() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"这个合约可以增发，而且管理员还在，安全吗？");

        assertEq(result.topic, retriever.TOPIC_CONTRACT());
        assertFalse(result.negated);
        assertTrue(_contains(result.response, unicode"存在明确的供应风险"));
    }

    function testNegationPreventsFalseMintRiskConclusion() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"这个合约不能增发，管理员还在，安全吗？");

        assertEq(result.topic, retriever.TOPIC_CONTRACT());
        assertTrue(result.negated);
        assertFalse(_contains(result.response, unicode"同时允许增发"));
        assertTrue(_contains(result.response, unicode"实际部署字节码"));
    }

    function testProxyAdminCombinationProducesUpgradeRisk() public view {
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"这是代理合约，管理员能升级，有什么风险？");

        assertEq(result.topic, retriever.TOPIC_CONTRACT());
        assertTrue(_contains(result.response, unicode"未来业务规则仍可改变"));
    }

    function testGreetingPreservesTrainedDialogueBehavior() public view {
        TinyAIRetrieverV5.RetrievalResult memory result = retriever.preview(alice, unicode"你好呀");

        assertEq(result.topic, retriever.TOPIC_DIALOGUE());
        assertEq(result.factCount, 1);
        assertEq(result.factIds[0], 9001);
        assertFalse(result.unknown);
        assertGt(bytes(result.response).length, 20);
        assertTrue(_contains(result.evidence, unicode"v3 训练分类器"));
    }

    function testExplicitFollowupUsesV5TopicMemory() public {
        vm.prank(alice);
        retriever.chat(unicode"什么是 BSC？");

        TinyAIRetrieverV5.RetrievalResult memory followup = retriever.preview(alice, unicode"继续说详细一点");
        assertTrue(followup.followedContext);
        assertEq(followup.topic, retriever.TOPIC_BSC());
        assertEq(followup.queryType, retriever.QUERY_FOLLOWUP());
        assertEq(followup.factIds[0], 1301);
    }

    function testChatPersistsAuditableMemory() public {
        vm.prank(alice);
        TinyAIRetrieverV5.RetrievalResult memory result = retriever.chat(unicode"钱包签名应该检查什么？");

        TinyAIRetrieverV5.Memory memory remembered = retriever.memoryOf(alice);
        assertEq(retriever.totalChats(), 1);
        assertEq(remembered.turns, 1);
        assertEq(remembered.lastTopic, retriever.TOPIC_WALLET());
        assertEq(remembered.lastIntent, result.intent);
        assertEq(remembered.rollingContext, result.nextContext);
    }

    function testPreviewAndTraceAreDeterministic() public view {
        string memory prompt = unicode"BSC 为什么使用 Gas？";
        TinyAIRetrieverV5.RetrievalResult memory first = retriever.preview(alice, prompt);
        TinyAIRetrieverV5.RetrievalResult memory second = retriever.preview(alice, prompt);

        assertEq(first.response, second.response);
        assertEq(first.evidence, second.evidence);
        assertEq(first.traceHash, second.traceHash);
        assertEq(keccak256(abi.encode(first.trace)), keccak256(abi.encode(second.trace)));
    }

    function testPreviewFitsProductGasCeiling() public view {
        uint256 beforeGas = gasleft();
        TinyAIRetrieverV5.RetrievalResult memory result =
            retriever.preview(alice, unicode"如果合约能增发并且管理员还能升级，风险是什么？");
        uint256 used = beforeGas - gasleft();

        assertEq(result.factCount, 3);
        assertLt(used, 15_000_000, "v5 retrieval exceeded the 15M gas product ceiling");
    }

    function testRejectsMissingModulesAndInvalidPrompt() public {
        vm.expectRevert(TinyAIRetrieverV5.InvalidClassifier.selector);
        new TinyAIRetrieverV5(TinyAIChat(address(0)), knowledge);

        vm.expectRevert(TinyAIRetrieverV5.InvalidKnowledge.selector);
        new TinyAIRetrieverV5(classifier, TinyAIKnowledgeV5(address(0)));

        vm.expectRevert(TinyAIRetrieverV5.EmptyPrompt.selector);
        retriever.preview(alice, "");

        bytes memory oversized = new bytes(281);
        for (uint256 index; index < oversized.length; ++index) {
            oversized[index] = "a";
        }
        vm.expectRevert(abi.encodeWithSelector(TinyAIRetrieverV5.PromptTooLong.selector, 281));
        retriever.preview(alice, string(oversized));
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
