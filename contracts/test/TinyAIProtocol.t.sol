// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

import {IBrainEngine} from "../src/protocol/IBrainEngine.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIComponents} from "../src/protocol/TinyAIComponents.sol";
import {TinyAIMarket} from "../src/protocol/TinyAIMarket.sol";
import {TinyAIProtocol} from "../src/protocol/TinyAIProtocol.sol";

contract MockBrainEngine is IBrainEngine {
    uint32 private immutable _version;
    string private _prefix;
    bool public healthy = true;

    constructor(uint32 version_, string memory prefix_) {
        _version = version_;
        _prefix = prefix_;
    }

    function setHealthy(bool healthy_) external {
        healthy = healthy_;
    }

    function engineVersion() external view returns (uint32) {
        return _version;
    }

    function infer(BrainInput calldata input) external view returns (BrainOutput memory output) {
        bool unknown = keccak256(bytes(input.prompt)) == keccak256(bytes(unicode"不知道"));
        output = BrainOutput({
            response: string.concat(_prefix, input.prompt),
            confidence: unknown ? 0 : 8_000,
            topic: unknown ? 0 : 1,
            variant: uint8(uint256(keccak256(abi.encode(input.dna, input.prompt))) % 4),
            unknown: unknown,
            neuralGenerated: !unknown,
            traceHash: keccak256(abi.encode(_version, input.aiId, input.memoryRoot, input.prompt))
        });
    }

    function integrityOk() external view returns (bool) {
        return healthy;
    }

    function truthBoundary() external pure returns (string memory) {
        return "mock brain for protocol lifecycle tests";
    }
}

contract TinyAIProtocolTest is Test {
    using stdStorage for StdStorage;

    uint256 private constant MEMORY_CELL = 1;
    uint256 private constant CURIOSITY_GENE = 2;
    uint256 private constant EMPATHY_GENE = 3;
    uint256 private constant HUMOR_GENE = 4;
    uint256 private constant CAUTION_GENE = 5;
    uint256 private constant EXPRESSION_CORE = 6;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant TREASURY = address(0xBEEF);

    TinyAIBrainRegistry private registry;
    TinyAIComponents private components;
    TinyAIProtocol private protocol;
    TinyAIMarket private market;
    MockBrainEngine private brainV1;

    function setUp() external {
        registry = new TinyAIBrainRegistry(address(this));
        components = new TinyAIComponents("ipfs://tinyai/{id}.json", address(this), TREASURY);
        brainV1 = new MockBrainEngine(1, "v1:");
        registry.publish(address(brainV1), "Genesis Brain V1", true);
        protocol = new TinyAIProtocol(registry, components, address(this), TREASURY);
        components.bindProtocol(address(protocol));
        market = new TinyAIMarket(address(protocol), address(components));

        components.defineComponent(MEMORY_CELL, components.EFFECT_MEMORY(), 0, 1, 30_000);
        components.defineComponent(CURIOSITY_GENE, components.EFFECT_PERSONALITY(), 0, 5, 15_000);
        components.defineComponent(EMPATHY_GENE, components.EFFECT_PERSONALITY(), 1, 5, 15_000);
        components.defineComponent(HUMOR_GENE, components.EFFECT_PERSONALITY(), 2, 5, 15_000);
        components.defineComponent(CAUTION_GENE, components.EFFECT_PERSONALITY(), 3, 5, 15_000);
        components.defineComponent(EXPRESSION_CORE, components.EFFECT_EXPRESSION(), 0, 1, 10_000);
        components.sealCatalog();

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    function testMintCreatesUniqueOnchainAI() external {
        uint256 first = _mint(ALICE, "MOMO", bytes32("seed-one"), false);
        uint256 second = _mint(ALICE, "NANA", bytes32("seed-two"), true);

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(protocol.ownerOf(first), ALICE);
        assertEq(protocol.aiName(first), "MOMO");

        TinyAIProtocol.AIState memory firstState = protocol.aiState(first);
        TinyAIProtocol.AIState memory secondState = protocol.aiState(second);
        assertEq(firstState.brainVersion, 1);
        assertEq(firstState.memoryCapacity, 1);
        assertFalse(firstState.autoUpgrade);
        assertFalse(firstState.publicChat);
        assertTrue(secondState.autoUpgrade);
        assertTrue(firstState.dna != secondState.dna);
        assertGe(firstState.curiosity, 32);
        assertLe(firstState.curiosity, 100);
        assertGt(bytes(protocol.tokenURI(first)).length, 200);

        uint256[] memory owned = protocol.tokensOfOwner(ALICE);
        assertEq(owned.length, 2);
        assertEq(owned[0], first);
        assertEq(owned[1], second);
    }

    function testOnlyCurrentOwnerCanChatAndGrowAI() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(TinyAIProtocol.NotAIOwner.selector, aiId));
        protocol.chatAI(aiId, unicode"你好");

        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory output = protocol.chatAI(aiId, unicode"你好");

        assertEq(output.response, unicode"v1:你好");
        TinyAIProtocol.AIState memory state = protocol.aiState(aiId);
        assertEq(state.turns, 1);
        assertEq(state.experience, 3);
        assertTrue(state.memoryRoot != bytes32(0));
        assertTrue(protocol.memoryAt(aiId, 0) != bytes32(0));
        assertEq(protocol.ownerOf(aiId), ALICE);
    }

    function testPreviewAndPublicChatControlsAreNotExposed() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        (bool previewOk,) =
            address(protocol).staticcall(abi.encodeWithSignature("previewAI(uint256,string)", aiId, unicode"你好"));
        (bool publicControlOk,) =
            address(protocol).call(abi.encodeWithSignature("setPublicChat(uint256,bool)", aiId, true));
        assertFalse(previewOk);
        assertFalse(publicControlOk);
        assertFalse(protocol.aiState(aiId).publicChat);
    }

    function testUnknownChatUsesHonestLowExperiencePath() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory output = protocol.chatAI(aiId, unicode"不知道");
        assertTrue(output.unknown);
        assertEq(protocol.aiState(aiId).experience, 1);
    }

    function testComponentsHaveConcretePermanentEffects() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        TinyAIProtocol.AIState memory beforeState = protocol.aiState(aiId);
        _mintComponents(ALICE, MEMORY_CELL, 2);
        _mintComponents(ALICE, CURIOSITY_GENE, 1);
        _mintComponents(ALICE, EXPRESSION_CORE, 2);

        vm.startPrank(ALICE);
        protocol.fuseComponent(aiId, MEMORY_CELL, 2);
        protocol.fuseComponent(aiId, CURIOSITY_GENE, 1);
        protocol.fuseComponent(aiId, EXPRESSION_CORE, 2);
        vm.stopPrank();

        TinyAIProtocol.AIState memory afterState = protocol.aiState(aiId);
        assertEq(afterState.memoryCapacity, 3);
        assertEq(afterState.curiosity, beforeState.curiosity + 5);
        assertEq(afterState.expressionLevel, 2);
        assertEq(afterState.skillMask, 0);
        assertEq(components.balanceOf(ALICE, MEMORY_CELL), 0);
    }

    function testPublishingV2CannotSilentlyRewriteV1AI() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        MockBrainEngine brainV2 = new MockBrainEngine(2, "v2:");
        registry.publish(address(brainV2), "Stronger Brain V2", true);

        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory oldOutput = protocol.chatAI(aiId, unicode"你好");
        assertEq(oldOutput.response, unicode"v1:你好");

        vm.prank(ALICE);
        protocol.upgradeBrain(aiId, 2);
        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory newOutput = protocol.chatAI(aiId, unicode"你好");
        assertEq(newOutput.response, unicode"v2:你好");
    }

    function testOwnerCanOptIntoAutomaticFutureBrains() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), true);
        MockBrainEngine brainV2 = new MockBrainEngine(2, "v2:");
        registry.publish(address(brainV2), "Stronger Brain V2", true);

        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory output = protocol.chatAI(aiId, unicode"你好");
        assertEq(output.response, unicode"v2:你好");
        assertEq(protocol.aiState(aiId).brainVersion, 2);
    }

    function testSealedAIRejectsEveryFutureMigration() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        vm.prank(ALICE);
        protocol.sealBrain(aiId);
        MockBrainEngine brainV2 = new MockBrainEngine(2, "v2:");
        registry.publish(address(brainV2), "Stronger Brain V2", true);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TinyAIProtocol.BrainIsSealed.selector, aiId));
        protocol.upgradeBrain(aiId, 2);
        assertEq(protocol.aiState(aiId).brainVersion, 1);
    }

    function testBrokenEngineDependencyFailsClosed() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        brainV1.setHealthy(false);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TinyAIBrainRegistry.EngineIntegrityFailed.selector, uint32(1)));
        protocol.chatAI(aiId, unicode"你好");
    }

    function testMarketTransfersAIAndReconcilesBNB() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        vm.startPrank(ALICE);
        protocol.approve(address(market), aiId);
        uint256 listingId = market.listAI(address(protocol), aiId, 1 ether);
        vm.stopPrank();

        vm.prank(BOB);
        market.buy{value: 1 ether}(listingId, 1);

        assertEq(protocol.ownerOf(aiId), BOB);
        assertEq(protocol.tokensOfOwner(ALICE).length, 0);
        uint256[] memory bobAIs = protocol.tokensOfOwner(BOB);
        assertEq(bobAIs.length, 1);
        assertEq(bobAIs[0], aiId);
        assertEq(market.MARKET_FEE_BPS(), 0);
        assertEq(market.owed(ALICE), 1 ether);
        assertEq(market.owed(TREASURY), 0);
        assertEq(address(market).balance, 1 ether);

        uint256 before = ALICE.balance;
        vm.prank(ALICE);
        market.withdraw();
        assertEq(ALICE.balance, before + 1 ether);
    }

    function testMarketSupportsPartialComponentSales() external {
        _mintComponents(ALICE, MEMORY_CELL, 5);
        vm.startPrank(ALICE);
        components.setApprovalForAll(address(market), true);
        uint256 listingId = market.listComponents(address(components), MEMORY_CELL, 3, 0.1 ether);
        vm.stopPrank();

        vm.prank(BOB);
        market.buy{value: 0.2 ether}(listingId, 2);

        assertEq(components.balanceOf(ALICE, MEMORY_CELL), 3);
        assertEq(components.balanceOf(BOB, MEMORY_CELL), 2);
        (,,,, uint96 remaining,) = market.listings(listingId);
        assertEq(remaining, 1);
        assertEq(market.owed(ALICE), 0.2 ether);
        assertEq(market.owed(TREASURY), 0);
    }

    function testMarketHasNoFeeAdministrationPath() external {
        (bool ok,) = address(market).call(abi.encodeWithSignature("setFee(uint16,address)", 100, TREASURY));
        assertFalse(ok);
        assertEq(market.MARKET_FEE_BPS(), 0);
    }

    function testMarketRejectsAssetsOutsideProtocol() external {
        vm.expectRevert(abi.encodeWithSelector(TinyAIMarket.UnsupportedAsset.selector, address(components)));
        market.listAI(address(components), 1, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(TinyAIMarket.UnsupportedAsset.selector, address(protocol)));
        market.listComponents(address(protocol), 1, 1, 1 ether);
    }

    function testAIPriceAndSupplyAreFixedAndRevenueGoesToTreasury() external {
        assertEq(protocol.MAX_AI_SUPPLY(), 10_000);
        assertEq(protocol.MINT_PRICE(), 0.0001 ether);
        assertEq(protocol.mintPrice(), 0.0001 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TinyAIProtocol.IncorrectPayment.selector, 0.0001 ether, 0));
        protocol.mintAI("MOMO", bytes32("seed"), false);

        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        assertEq(protocol.ownerOf(aiId), ALICE);
        assertEq(address(protocol).balance, 0.0001 ether);

        uint256 before = TREASURY.balance;
        protocol.withdraw();
        assertEq(TREASURY.balance, before + 0.0001 ether);
        assertEq(address(protocol).balance, 0);
    }

    function testAIHardCapAllowsTenThousandAndRejectsNextMint() external {
        stdstore.target(address(protocol)).sig(protocol.nextAIId.selector).checked_write(10_000);
        stdstore.target(address(protocol)).sig(protocol.totalSupply.selector).checked_write(9_999);
        uint256 lastAI = _mint(ALICE, "LAST", bytes32("last-seed"), false);
        assertEq(lastAI, 10_000);
        assertEq(protocol.totalSupply(), 10_000);

        uint256 price = protocol.MINT_PRICE();
        vm.expectRevert(TinyAIProtocol.AISupplyCapReached.selector);
        vm.prank(ALICE);
        protocol.mintAI{value: price}("OVER", bytes32("over-seed"), false);
    }

    function testGenesisComponentCatalogIsFixedAtOneHundredThousand() external {
        assertEq(components.MAX_COMPONENT_SUPPLY(), 100_000);
        assertEq(components.MINT_PRICE(), 0.0001 ether);
        assertEq(components.totalDefinedCap(), 100_000);
        assertTrue(components.catalogSealed());

        assertEq(components.definition(MEMORY_CELL).cap, 30_000);
        assertEq(components.definition(CURIOSITY_GENE).cap, 15_000);
        assertEq(components.definition(EMPATHY_GENE).cap, 15_000);
        assertEq(components.definition(HUMOR_GENE).cap, 15_000);
        assertEq(components.definition(CAUTION_GENE).cap, 15_000);
        assertEq(components.definition(EXPRESSION_CORE).cap, 10_000);

        uint8 skillEffect = components.EFFECT_SKILL();
        vm.expectRevert(TinyAIComponents.CatalogAlreadySealed.selector);
        components.defineComponent(7, skillEffect, 0, 1, 1);
    }

    function testComponentMintRevenueGoesToTreasuryAndBurnDoesNotReopenSupply() external {
        _mintComponents(ALICE, MEMORY_CELL, 2);
        assertEq(components.totalMinted(), 2);
        assertEq(address(components).balance, 0.0002 ether);

        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        vm.prank(ALICE);
        protocol.fuseComponent(aiId, MEMORY_CELL, 2);
        assertEq(components.balanceOf(ALICE, MEMORY_CELL), 0);
        assertEq(components.totalMinted(), 2);

        uint256 before = TREASURY.balance;
        components.withdraw();
        assertEq(TREASURY.balance, before + 0.0002 ether);
        assertEq(address(components).balance, 0);
    }

    function testCommittedChatAcceptsNoProtocolFee() external {
        uint256 aiId = _mint(ALICE, "MOMO", bytes32("seed"), false);
        vm.prank(ALICE);
        (bool ok,) = address(protocol).call{value: 1}(abi.encodeCall(TinyAIProtocol.chatAI, (aiId, unicode"你好")));
        assertFalse(ok);
        assertEq(address(protocol).balance, 0.0001 ether);
    }

    function _mint(address owner, string memory name, bytes32 seed, bool autoUpgrade) private returns (uint256 aiId) {
        uint256 price = protocol.MINT_PRICE();
        vm.prank(owner);
        aiId = protocol.mintAI{value: price}(name, seed, autoUpgrade);
    }

    function _mintComponents(address owner, uint256 componentId, uint64 amount) private {
        uint256 price = uint256(components.MINT_PRICE()) * amount;
        vm.prank(owner);
        components.publicMint{value: price}(componentId, amount);
    }
}
