// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {FixedSupplyChatToken} from "../src/FixedSupplyChatToken.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";

contract TinyAIChatTest is Test {
    bytes32 private constant CORPUS_SHA256 = 0x9bd76b2daefa3ac5a59852e3f8fa2e46bae52846b26b884918ac82f0b3cac8e7;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 private constant ALICE_KEY = 0xA11CE;
    address private alice;
    address private treasury = makeAddr("treasury");
    address private liquidity = makeAddr("liquidity");
    address private community = makeAddr("community");

    TinyAIModelCard private model;
    FixedSupplyChatToken private token;
    TinyAIChat private chat;

    function setUp() public {
        alice = vm.addr(ALICE_KEY);
        address[22] memory weights;
        for (uint256 index; index < weights.length; ++index) {
            weights[index] = address(
                new BytecodeBlob(vm.readFileBinary(string.concat("../model/build/model-", vm.toString(index), ".bin")))
            );
        }
        address zh = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-zh.bin")));
        address en = address(new BytecodeBlob(vm.readFileBinary("../model/build/lexicon-en.bin")));
        model = new TinyAIModelCard(weights, zh, en, CORPUS_SHA256);
        token = new FixedSupplyChatToken("TinyAI Test Token", "TAIT", treasury, liquidity, community);
        chat = new TinyAIChat(model, token, treasury, 10 ether, 2_500);

        vm.prank(treasury);
        assertTrue(token.transfer(alice, 1_000 ether));
    }

    function testModelCardIntegrityAndShape() public view {
        assertTrue(model.integrityOk());
        assertEq(model.VERSION(), 3);
        assertEq(model.publishedAt(), 1_786_838_400);
        assertEq(model.ACTIVE_FEATURES(), 13_531);
        assertEq(model.INTENT_COUNT(), 27);
        for (uint256 index; index < 21; ++index) {
            assertEq(model.weightsBlobs(index).code.length, 24_001);
        }
        assertEq(model.weightsBlobs(21).code.length, 10_255);
        assertEq(model.zhLexiconBlob().code.length, 15_280);
        assertEq(model.enLexiconBlob().code.length, 14_917);
    }

    function testPythonSolidityIntentParity() public view {
        _assertIntent(unicode"你好，你是谁", 0, true);
        _assertIntent(unicode"这次聊天真的在链上推理吗", 3, true);
        _assertIntent(unicode"一次聊天需要多少 Gas", 12, true);
        _assertIntent(unicode"管理员能升级模型吗", 24, true);
        _assertIntent(unicode"我今天终于成功了", 18, true);
        _assertIntent(unicode"我的交易为什么失败", 11, true);
        _assertIntent("How do I protect my wallet?", 10, false);
        _assertIntent("Tell me the live BNB price", 4, false);
        _assertIntent("Who can replace the model weights?", 24, false);
        _assertIntent("Give me a fun onchain AI idea", 16, false);
    }

    function testPreviewIsDeterministic() public view {
        TinyAIChat.InferenceResult memory first = chat.preview(alice, unicode"你好，你是谁");
        TinyAIChat.InferenceResult memory second = chat.preview(alice, unicode"你好，你是谁");
        assertEq(first.intent, second.intent);
        assertEq(first.variant, second.variant);
        assertEq(first.response, second.response);
        assertEq(first.nextContext, second.nextContext);
    }

    function testFollowupResolvesToPriorTopicOnchain() public {
        vm.prank(alice);
        token.approve(address(chat), 20 ether);
        vm.prank(alice);
        TinyAIChat.InferenceResult memory first = chat.chat(unicode"Gas 是什么");
        assertEq(first.intent, 12);

        vm.prank(alice);
        TinyAIChat.InferenceResult memory second = chat.chat(unicode"继续说");
        assertEq(second.intent, 12);
        assertTrue(second.followedContext);
        assertEq(second.secondaryIntent, chat.NO_SECONDARY_INTENT());
        assertEq(chat.memoryOf(alice).lastIntent, 12);

        TinyAIChat.InferenceResult memory noHistory = chat.preview(makeAddr("new-user"), unicode"继续说");
        assertEq(noHistory.intent, 26);
        assertFalse(noHistory.followedContext);
    }

    function testMultiTopicHeadCanComposeTwoOnchainAnswers() public view {
        TinyAIChat.InferenceResult memory result =
            chat.preview(alice, "my transaction is stuck and I cannot afford the gas");
        assertTrue(result.intent == 11 || result.intent == 12);
        assertTrue(result.secondaryIntent == 11 || result.secondaryIntent == 12);
        assertTrue(result.intent != result.secondaryIntent);
        assertGt(bytes(result.response).length, 200);
    }

    function testDataBlobsStopWhenCalled() public {
        address blob = model.weightsBlobs(0);
        assertEq(uint8(blob.code[0]), 0);
        (bool ok, bytes memory output) = blob.call("");
        assertTrue(ok);
        assertEq(output.length, 0);
    }

    function testChatChargesTokenBurnsAndUpdatesMemory() public {
        vm.prank(alice);
        token.approve(address(chat), 10 ether);
        uint256 treasuryBefore = token.balanceOf(treasury);
        uint256 burnBefore = token.balanceOf(chat.BURN_SINK());

        vm.prank(alice);
        TinyAIChat.InferenceResult memory result = chat.chat(unicode"一次聊天需要多少 Gas");

        assertEq(result.intent, 12);
        assertGt(bytes(result.response).length, 30);
        assertEq(token.balanceOf(alice), 990 ether);
        assertEq(token.balanceOf(treasury) - treasuryBefore, 7.5 ether);
        assertEq(token.balanceOf(chat.BURN_SINK()) - burnBefore, 2.5 ether);
        assertEq(chat.totalChats(), 1);

        TinyAIChat.Memory memory remembered = chat.memoryOf(alice);
        assertEq(remembered.turns, 1);
        assertEq(remembered.lastIntent, 12);
        assertEq(remembered.rollingContext, result.nextContext);
    }

    function testChatWithPermitNeedsNoApprovalTransaction() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(alice);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(chat), 10 ether, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        vm.prank(alice);
        TinyAIChat.InferenceResult memory result = chat.chatWithPermit("How do I protect my wallet?", deadline, v, r, s);

        assertEq(result.intent, 10);
        assertEq(token.nonces(alice), 1);
        assertEq(token.allowance(alice, address(chat)), 0);
    }

    function testPreviewGasBelowProductCeiling() public view {
        uint256 beforeGas = gasleft();
        TinyAIChat.InferenceResult memory result =
            chat.preview(alice, unicode"这个链上模型为什么算真 AI，它安全吗？");
        uint256 used = beforeGas - gasleft();
        assertGt(bytes(result.response).length, 30);
        assertLt(used, 15_000_000, "preview inference exceeded the 15M gas product ceiling");
    }

    function testRejectsEmptyAndOversizedPrompts() public {
        vm.expectRevert(TinyAIChat.EmptyPrompt.selector);
        chat.preview(alice, "");

        bytes memory oversized = new bytes(281);
        for (uint256 i; i < oversized.length; ++i) {
            oversized[i] = "a";
        }
        vm.expectRevert(abi.encodeWithSelector(TinyAIChat.PromptTooLong.selector, 281));
        chat.preview(alice, string(oversized));
    }

    function testTokenSupplyAndAllocationAreFixed() public view {
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(treasury) + token.balanceOf(alice), token.MAX_SUPPLY() * 6_500 / 10_000);
        assertEq(token.balanceOf(liquidity), token.MAX_SUPPLY() * 2_000 / 10_000);
        assertEq(token.balanceOf(community), token.MAX_SUPPLY() * 1_500 / 10_000);
    }

    function testFreeChatNeedsNoToken() public {
        TinyAIChat freeChat = new TinyAIChat(model, IERC20(address(0)), address(0), 0, 0);

        vm.prank(alice);
        TinyAIChat.InferenceResult memory result = freeChat.chat(unicode"代理合约是什么");

        assertEq(result.intent, 6);
        assertEq(freeChat.totalChats(), 1);
        assertEq(freeChat.memoryOf(alice).turns, 1);
    }

    function testRejectsInvalidFeeConfiguration() public {
        vm.expectRevert(TinyAIChat.InvalidFeeConfiguration.selector);
        new TinyAIChat(model, IERC20(address(0)), treasury, 1 ether, 0);

        vm.expectRevert(TinyAIChat.InvalidFeeConfiguration.selector);
        new TinyAIChat(model, token, address(0), 1 ether, 0);

        vm.expectRevert(TinyAIChat.InvalidFeeConfiguration.selector);
        new TinyAIChat(model, token, treasury, 1 ether, 10_001);
    }

    function testModelCardRejectsCorruptHeaders() public {
        address[22] memory weightBlobs;
        for (uint256 index; index < weightBlobs.length; ++index) {
            weightBlobs[index] = model.weightsBlobs(index);
        }
        address zhLexiconBlob = model.zhLexiconBlob();
        address enLexiconBlob = model.enLexiconBlob();
        bytes memory corruptWeights = vm.readFileBinary("../model/build/model-0.bin");
        corruptWeights[0] = 0x00;
        weightBlobs[0] = address(new BytecodeBlob(corruptWeights));

        vm.expectRevert(TinyAIModelCard.InvalidModelHeader.selector);
        new TinyAIModelCard(weightBlobs, zhLexiconBlob, enLexiconBlob, CORPUS_SHA256);

        bytes memory corruptLexicon = vm.readFileBinary("../model/build/lexicon-zh.bin");
        corruptLexicon[8] = 0x01;
        address badZh = address(new BytecodeBlob(corruptLexicon));

        for (uint256 index; index < weightBlobs.length; ++index) {
            weightBlobs[index] = model.weightsBlobs(index);
        }
        vm.expectRevert(abi.encodeWithSelector(TinyAIModelCard.InvalidLexiconHeader.selector, badZh, 0));
        new TinyAIModelCard(weightBlobs, badZh, enLexiconBlob, CORPUS_SHA256);
    }

    function testMemoryIsIsolatedPerWallet() public {
        address bob = makeAddr("bob");
        vm.prank(alice);
        token.approve(address(chat), 10 ether);
        vm.prank(alice);
        chat.chat(unicode"我今天终于成功了");

        TinyAIChat.Memory memory aliceMemory = chat.memoryOf(alice);
        TinyAIChat.Memory memory bobMemory = chat.memoryOf(bob);
        assertEq(aliceMemory.turns, 1);
        assertEq(aliceMemory.mood, 1);
        assertEq(bobMemory.turns, 0);
        assertEq(bobMemory.rollingContext, bytes32(0));
    }

    function testMalformedUtf8CannotEscapeBounds() public view {
        bytes memory malformed = hex"f080808061fffe";
        TinyAIChat.InferenceResult memory first = chat.preview(alice, string(malformed));
        TinyAIChat.InferenceResult memory second = chat.preview(alice, string(malformed));
        assertEq(first.intent, second.intent);
        assertEq(first.response, second.response);
    }

    function _assertIntent(string memory prompt, uint8 expected, bool chinese) private view {
        TinyAIChat.InferenceResult memory result = chat.preview(address(0xBEEF), prompt);
        assertEq(result.intent, expected, prompt);
        assertEq(result.chinese, chinese, prompt);
        assertGt(bytes(result.response).length, 20, prompt);
    }
}
