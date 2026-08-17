// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {TinyAIKnowledgeV4} from "../src/TinyAIKnowledgeV4.sol";
import {TinyAIReasonerV4} from "../src/TinyAIReasonerV4.sol";

contract TinyAIReasonerV4Test is Test {
    TinyAIKnowledgeV4 private knowledge;
    TinyAIReasonerV4 private reasoner;

    address private alice = makeAddr("alice");

    function setUp() public {
        knowledge = new TinyAIKnowledgeV4();
        reasoner = new TinyAIReasonerV4(knowledge);
    }

    function testModulesFitEip170AndIntegrityIsLocked() public view {
        assertLt(address(knowledge).code.length, 24_576);
        assertLt(address(reasoner).code.length, 24_576);
        assertEq(address(reasoner.knowledge()), address(knowledge));
        assertEq(reasoner.knowledgeCodeHash(), address(knowledge).codehash);
        assertEq(reasoner.KNOWLEDGE_HASH(), knowledge.KNOWLEDGE_HASH());
        assertTrue(reasoner.integrityOk());
    }

    function testRejectsMissingKnowledgeModule() public {
        vm.expectRevert(TinyAIReasonerV4.InvalidKnowledge.selector);
        new TinyAIReasonerV4(TinyAIKnowledgeV4(address(0)));
    }

    function testBscDefinitionDerivesFactsInsteadOfSelectingIdentityReply() public view {
        TinyAIReasonerV4.ReasoningResult memory result = reasoner.preview(alice, unicode"你知道什么是 BSC 吗", 1);

        assertEq(result.domain, reasoner.DOMAIN_BSC());
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_BSC_EVM()));
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_BSC_USES_BNB()));
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_BSC_PROGRAMMABLE()));
        assertTrue(_contains(result.response, "BNB Smart Chain"));
        assertGt(result.stepCount, 4);
    }

    function testHumanQuestionProducesHumanConclusion() public view {
        TinyAIReasonerV4.ReasoningResult memory result =
            reasoner.preview(alice, unicode"你知道什么是人类吗", 1);

        assertEq(result.domain, reasoner.DOMAIN_HUMAN());
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_HUMAN_BIOSOCIAL()));
        assertTrue(_contains(result.response, unicode"生物个体"));
        assertFalse(_contains(result.response, unicode"电子宠物"));
    }

    function testGasBudgetIsNotMistakenForIntelligence() public view {
        TinyAIReasonerV4.ReasoningResult memory result =
            reasoner.preview(alice, unicode"如果把 Gas 提高十倍，AI 会聪明十倍吗？", 1);

        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_GAS_NOT_INTELLIGENCE()));
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_ARCHITECTURE_MATTERS()));
        assertTrue(_contains(result.response, unicode"不是智商倍率"));
        assertTrue(_contains(result.response, unicode"算法不变"));
    }

    function testDeepModeActuallyCompletesAnotherReasoningPass() public view {
        string memory prompt = unicode"如果把 Gas 提高十倍，AI 会聪明十倍吗？";
        TinyAIReasonerV4.ReasoningResult memory quick = reasoner.preview(alice, prompt, 0);
        TinyAIReasonerV4.ReasoningResult memory deep = reasoner.preview(alice, prompt, 1);

        assertTrue(_has(quick.conclusions, reasoner.CONCLUSION_GAS_NOT_INTELLIGENCE()));
        assertFalse(_has(quick.conclusions, reasoner.CONCLUSION_ARCHITECTURE_MATTERS()));
        assertTrue(_has(deep.conclusions, reasoner.CONCLUSION_ARCHITECTURE_MATTERS()));
        assertGt(deep.stepCount, quick.stepCount);
        assertTrue(_contains(deep.response, unicode"深度模式"));
    }

    function testCombinesMintAndAdminIntoSupplyRisk() public view {
        TinyAIReasonerV4.ReasoningResult memory result =
            reasoner.preview(alice, unicode"这个合约可以增发，而且管理员还在，安全吗？", 1);

        assertEq(result.domain, reasoner.DOMAIN_CONTRACT_SECURITY());
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_SUPPLY_RISK()));
        assertTrue(_contains(result.response, unicode"供应风险"));
    }

    function testCombinesProxyAndAdminIntoUpgradeRisk() public view {
        TinyAIReasonerV4.ReasoningResult memory result =
            reasoner.preview(alice, unicode"这是代理合约，管理员能升级，有什么风险？", 1);

        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_UPGRADE_RISK()));
        assertTrue(_contains(result.response, unicode"规则仍能改变"));
    }

    function testUnknownQuestionProducesPromptConditionedSpeculation() public view {
        string memory prompt = unicode"量子香蕉今晚做梦吗";
        TinyAIReasonerV4.ReasoningResult memory result = reasoner.preview(alice, prompt, 1);

        assertEq(result.domain, reasoner.DOMAIN_UNKNOWN());
        assertTrue(_has(result.facts, reasoner.FACT_OPEN_WORLD()));
        assertTrue(_has(result.facts, reasoner.FACT_PROMPT_CONDITIONED()));
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_SPECULATIVE_ANSWER()));
        assertTrue(_contains(result.response, prompt));
        assertTrue(_contains(result.response, unicode"低置信度推测"));
        assertFalse(_contains(result.response, unicode"承认不知道"));
    }

    function testUniversalGeneratorAnswersUnseenChineseQuestionShapes() public view {
        string[4] memory prompts = [
            unicode"恐龙为什么灭绝？",
            unicode"怎么做红烧肉？",
            unicode"比较木星和一杯咖啡",
            unicode"蓝色星期八会不会唱歌？"
        ];
        uint8[4] memory expectedTypes =
            [reasoner.QUERY_WHY(), reasoner.QUERY_HOW(), reasoner.QUERY_COMPARE(), reasoner.QUERY_UNKNOWN()];

        for (uint256 index; index < prompts.length; ++index) {
            TinyAIReasonerV4.ReasoningResult memory result = reasoner.preview(alice, prompts[index], 1);
            assertEq(result.domain, reasoner.DOMAIN_UNKNOWN());
            assertEq(result.queryType, expectedTypes[index]);
            assertTrue(_has(result.conclusions, reasoner.CONCLUSION_SPECULATIVE_ANSWER()));
            assertTrue(_contains(result.response, prompts[index]));
            assertGt(bytes(result.response).length, bytes(prompts[index]).length);
        }
    }

    function testUniversalGeneratorAnswersUnseenEnglishQuestion() public view {
        string memory prompt = "Why do cats dream?";
        TinyAIReasonerV4.ReasoningResult memory result = reasoner.preview(alice, prompt, 1);

        assertEq(result.domain, reasoner.DOMAIN_UNKNOWN());
        assertEq(result.queryType, reasoner.QUERY_WHY());
        assertFalse(result.chinese);
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_SPECULATIVE_ANSWER()));
        assertTrue(_contains(result.response, prompt));
        assertTrue(_contains(result.response, "low-confidence hypothesis"));
    }

    function testArbitraryPromptAlwaysReturnsDeterministicNonEmptyAnswer() public view {
        string[5] memory prompts = [
            unicode"月亮是奶酪做的吗",
            unicode"请设计一座住在云里的城市",
            unicode"石头有没有记忆",
            "zxqv 1739 ???",
            unicode"如果时间倒流会怎样"
        ];

        for (uint256 index; index < prompts.length; ++index) {
            TinyAIReasonerV4.ReasoningResult memory first = reasoner.preview(alice, prompts[index], 0);
            TinyAIReasonerV4.ReasoningResult memory second = reasoner.preview(alice, prompts[index], 0);
            assertGt(bytes(first.response).length, 0);
            assertEq(first.response, second.response);
            assertEq(first.traceHash, second.traceHash);
        }
    }

    function testOnlyExplicitFollowupUsesWalletMemory() public {
        vm.prank(alice);
        reasoner.chat(unicode"什么是 BSC", 1);

        TinyAIReasonerV4.ReasoningResult memory followup = reasoner.preview(alice, unicode"继续说", 1);
        assertTrue(followup.followedContext);
        assertEq(followup.domain, reasoner.DOMAIN_BSC());

        TinyAIReasonerV4.ReasoningResult memory unrelated = reasoner.preview(alice, unicode"人类是什么", 1);
        assertFalse(unrelated.followedContext);
        assertEq(unrelated.domain, reasoner.DOMAIN_HUMAN());
    }

    function testChatPersistsAuditableMemory() public {
        vm.prank(alice);
        TinyAIReasonerV4.ReasoningResult memory result = reasoner.chat(unicode"钱包签名安全吗", 1);

        TinyAIReasonerV4.Memory memory remembered = reasoner.memoryOf(alice);
        assertEq(reasoner.totalChats(), 1);
        assertEq(remembered.turns, 1);
        assertEq(remembered.lastDomain, reasoner.DOMAIN_WALLET());
        assertEq(remembered.rollingContext, result.nextContext);
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_PROTECT_KEY()));
        assertTrue(_has(result.conclusions, reasoner.CONCLUSION_VERIFY_SIGNATURE()));
    }

    function testPreviewAndTraceAreDeterministic() public view {
        TinyAIReasonerV4.ReasoningResult memory first = reasoner.preview(alice, unicode"什么是 BSC", 1);
        TinyAIReasonerV4.ReasoningResult memory second = reasoner.preview(alice, unicode"什么是 BSC", 1);

        assertEq(first.response, second.response);
        assertEq(first.traceHash, second.traceHash);
        assertEq(first.nextContext, second.nextContext);
        assertEq(keccak256(abi.encode(first.trace)), keccak256(abi.encode(second.trace)));
    }

    function testTraceWordsDecodeToReplayableStages() public view {
        string memory prompt = unicode"什么是 BSC";
        TinyAIReasonerV4.ReasoningResult memory result = reasoner.preview(alice, prompt, 1);
        (uint8 firstOpcode,,,,,,) = reasoner.decodeTraceWord(result.trace[0]);
        (uint8 lastOpcode,,,,,,) = reasoner.decodeTraceWord(result.trace[result.stepCount - 1]);

        assertEq(firstOpcode, reasoner.OP_PARSE());
        assertEq(lastOpcode, reasoner.OP_RENDER());
        assertEq(
            result.traceHash,
            keccak256(
                abi.encode(
                    reasoner.KNOWLEDGE_HASH(),
                    alice,
                    bytes32(0),
                    keccak256(bytes(prompt)),
                    uint8(1),
                    result.domain,
                    result.queryType,
                    result.confidence,
                    result.facts,
                    result.conclusions,
                    result.stepCount,
                    result.trace
                )
            )
        );
    }

    function testDeepPreviewFitsProductGasCeiling() public view {
        uint256 beforeGas = gasleft();
        TinyAIReasonerV4.ReasoningResult memory result =
            reasoner.preview(alice, unicode"如果把 Gas 提高十倍，链上 AI 会聪明十倍吗？", 1);
        uint256 used = beforeGas - gasleft();

        assertGt(bytes(result.response).length, 30);
        assertLt(used, 15_000_000, "v4 deep reasoning exceeded the 15M gas product ceiling");
    }

    function testRejectsInvalidInputs() public {
        vm.expectRevert(TinyAIReasonerV4.EmptyPrompt.selector);
        reasoner.preview(alice, "", 0);

        vm.expectRevert(abi.encodeWithSelector(TinyAIReasonerV4.InvalidDepth.selector, 2));
        reasoner.preview(alice, "hello", 2);

        bytes memory oversized = new bytes(281);
        for (uint256 index; index < oversized.length; ++index) {
            oversized[index] = "a";
        }
        vm.expectRevert(abi.encodeWithSelector(TinyAIReasonerV4.PromptTooLong.selector, 281));
        reasoner.preview(alice, string(oversized), 0);
    }

    function _has(uint64 bits, uint64 flag) private pure returns (bool) {
        return bits & flag != 0;
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
