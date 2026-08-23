// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {ExactERC20Payment} from "../src/protocol/ExactERC20Payment.sol";
import {IBrainEngine} from "../src/protocol/IBrainEngine.sol";
import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIHolderVault} from "../src/protocol/TinyAIHolderVault.sol";
import {TinyAITokenComponents} from "../src/protocol/TinyAITokenComponents.sol";
import {TinyAITokenMarket} from "../src/protocol/TinyAITokenMarket.sol";
import {TinyAITokenProtocol} from "../src/protocol/TinyAITokenProtocol.sol";

contract TokenModePaymentToken is ERC20 {
    constructor() ERC20("TinyAI Utility", "TAI") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenModeTaxToken is ERC20 {
    address private constant FEE_SINK = address(0xFEE);

    constructor() ERC20("Taxed TinyAI", "TAXAI") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 10;
            super._update(from, FEE_SINK, fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

contract TokenModeMockBrain is IBrainEngine {
    uint32 private immutable _version;

    constructor(uint32 version_) {
        _version = version_;
    }

    function engineVersion() external view returns (uint32) {
        return _version;
    }

    function infer(BrainInput calldata input) external pure returns (BrainOutput memory output) {
        output = BrainOutput({
            response: string.concat("token:", input.prompt),
            confidence: 8_000,
            topic: 1,
            variant: 0,
            unknown: false,
            neuralGenerated: true,
            traceHash: keccak256(abi.encode(input.aiId, input.prompt))
        });
    }

    function integrityOk() external pure returns (bool) {
        return true;
    }

    function truthBoundary() external pure returns (string memory) {
        return "token mode test brain";
    }
}

contract TinyAITokenModeTest is Test {
    uint256 private constant AI_PRICE = 500 ether;
    uint128 private constant COMPONENT_PRICE = 500 ether;
    uint256 private constant CHAT_PRICE = 0;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant TREASURY = address(0xBEEF);

    TokenModePaymentToken private token;
    TokenModePaymentToken private rewardToken;
    TinyAIBrainRegistry private registry;
    TinyAIHolderVault private holderVault;
    TinyAITokenComponents private components;
    TinyAITokenProtocol private protocol;
    TinyAITokenMarket private market;

    function setUp() external {
        token = new TokenModePaymentToken();
        rewardToken = new TokenModePaymentToken();
        token.mint(ALICE, 1_000_000 ether);
        token.mint(BOB, 1_000_000 ether);

        registry = new TinyAIBrainRegistry(address(this));
        registry.publish(address(new TokenModeMockBrain(1)), "Token Brain V1", true);
        holderVault = new TinyAIHolderVault(rewardToken, address(this));
        components =
            new TinyAITokenComponents("ipfs://tinyai-token/{id}.json", address(this), TREASURY, token, COMPONENT_PRICE);
        protocol = new TinyAITokenProtocol(
            registry, components, holderVault, address(this), TREASURY, token, AI_PRICE, CHAT_PRICE
        );
        holderVault.bindProtocol(address(protocol));
        components.bindProtocol(address(protocol));
        market = new TinyAITokenMarket(address(protocol), address(components), token);
        _defineCatalog(components);

        vm.prank(ALICE);
        token.approve(address(protocol), type(uint256).max);
        vm.prank(ALICE);
        token.approve(address(components), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(market), type(uint256).max);
    }

    function testMintChargesFiveHundredTokensAndChatRemainsFree() external {
        assertEq(address(protocol.paymentToken()), address(token));
        assertEq(address(components.paymentToken()), address(token));
        assertEq(protocol.MINT_PRICE(), AI_PRICE);
        assertEq(components.MINT_PRICE(), COMPONENT_PRICE);
        assertEq(protocol.CHAT_PRICE(), CHAT_PRICE);

        uint256 beforeTreasury = token.balanceOf(TREASURY);
        uint256 aiId = _mintAI(ALICE, "MOMO");
        assertEq(token.balanceOf(TREASURY) - beforeTreasury, AI_PRICE);
        assertEq(token.balanceOf(address(protocol)), 0);

        vm.prank(ALICE);
        IBrainEngine.BrainOutput memory output = protocol.chatAI(aiId, unicode"你好");
        assertEq(output.response, unicode"token:你好");
        assertEq(token.balanceOf(TREASURY) - beforeTreasury, AI_PRICE);
        assertEq(protocol.aiState(aiId).turns, 1);
    }

    function testBrainUpgradeDoesNotChargeTiny() external {
        uint256 aiId = _mintAI(ALICE, "MOMO");
        registry.publish(address(new TokenModeMockBrain(2)), "Token Brain V2", true);
        uint256 aliceBefore = token.balanceOf(ALICE);
        uint256 treasuryBefore = token.balanceOf(TREASURY);

        vm.prank(ALICE);
        protocol.upgradeBrain(aiId, 2);

        assertEq(protocol.aiState(aiId).brainVersion, 2);
        assertEq(token.balanceOf(ALICE), aliceBefore);
        assertEq(token.balanceOf(TREASURY), treasuryBefore);
    }

    function testMintRequiresAllowanceAndNeverAcceptsNativeBNB() external {
        vm.prank(BOB);
        vm.expectRevert();
        protocol.mintAI("NO-ALLOWANCE", bytes32("seed"), false);

        vm.deal(BOB, 1 ether);
        vm.prank(BOB);
        (bool ok,) = address(protocol).call{value: 1}(
            abi.encodeCall(TinyAITokenProtocol.mintAI, ("NO-BNB", bytes32("seed"), false))
        );
        assertFalse(ok);
    }

    function testPredictedFlapCACanBeBoundBeforeLaunchButCannotMint() external {
        IERC20 predictedToken = IERC20(address(0x12347777));
        TinyAITokenComponents predictedComponents =
            new TinyAITokenComponents("", address(this), TREASURY, predictedToken, COMPONENT_PRICE);
        TinyAIHolderVault predictedVault = new TinyAIHolderVault(rewardToken, address(this));
        TinyAITokenProtocol predictedProtocol = new TinyAITokenProtocol(
            registry, predictedComponents, predictedVault, address(this), TREASURY, predictedToken, AI_PRICE, 0
        );
        predictedVault.bindProtocol(address(predictedProtocol));
        predictedComponents.bindProtocol(address(predictedProtocol));
        new TinyAITokenMarket(address(predictedProtocol), address(predictedComponents), predictedToken);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(ExactERC20Payment.PaymentTokenNotDeployed.selector, address(predictedToken))
        );
        predictedProtocol.mintAI("NOT-LIVE", bytes32("seed"), false);
        assertEq(predictedProtocol.totalSupply(), 0);
        assertEq(predictedVault.registeredAICount(), 0);
    }

    function testComponentMintUsesSameTokenAndFusionStillBurnsSupply() external {
        uint256 aiId = _mintAI(ALICE, "MOMO");
        uint256 beforeTreasury = token.balanceOf(TREASURY);

        vm.prank(ALICE);
        components.publicMint(1, 2);
        assertEq(token.balanceOf(TREASURY) - beforeTreasury, uint256(COMPONENT_PRICE) * 2);
        assertEq(components.balanceOf(ALICE, 1), 2);

        vm.prank(ALICE);
        protocol.fuseComponent(aiId, 1, 2);
        assertEq(components.balanceOf(ALICE, 1), 0);
        assertEq(components.totalMinted(), 2);
        assertEq(protocol.aiState(aiId).memoryCapacity, 3);
    }

    function testMarketPaysSellerOneHundredPercentWithoutCustody() external {
        uint256 aiId = _mintAI(ALICE, "MOMO");
        vm.startPrank(ALICE);
        protocol.approve(address(market), aiId);
        uint256 listingId = market.listAI(address(protocol), aiId, 500 ether);
        vm.stopPrank();

        uint256 sellerBefore = token.balanceOf(ALICE);
        vm.prank(BOB);
        market.buy(listingId, 1);

        assertEq(protocol.ownerOf(aiId), BOB);
        assertEq(token.balanceOf(ALICE) - sellerBefore, 500 ether);
        assertEq(token.balanceOf(address(market)), 0);
        assertEq(market.MARKET_FEE_BPS(), 0);
    }

    function testFlapRewardsAreSharedEquallyPerAI() external {
        vm.prank(BOB);
        token.approve(address(protocol), type(uint256).max);
        uint256 aliceAI1 = _mintAI(ALICE, "ALICE-1");
        uint256 aliceAI2 = _mintAI(ALICE, "ALICE-2");
        uint256 bobAI = _mintAI(BOB, "BOB-1");
        rewardToken.mint(address(holderVault), 300 ether);

        holderVault.sync();
        assertEq(holderVault.claimable(aliceAI1), 100 ether);
        assertEq(holderVault.claimable(aliceAI2), 100 ether);
        assertEq(holderVault.claimable(bobAI), 100 ether);

        uint256[] memory aliceIds = new uint256[](2);
        aliceIds[0] = aliceAI1;
        aliceIds[1] = aliceAI2;
        vm.prank(ALICE);
        holderVault.claim(aliceIds, ALICE);

        uint256[] memory bobIds = new uint256[](1);
        bobIds[0] = bobAI;
        vm.prank(BOB);
        holderVault.claim(bobIds, BOB);

        assertEq(rewardToken.balanceOf(ALICE), 200 ether);
        assertEq(rewardToken.balanceOf(BOB), 100 ether);
        assertEq(holderVault.totalReceived(), 300 ether);
        assertEq(holderVault.totalClaimed(), 300 ether);
    }

    function testFlapERC20PingSyncsRewardsAndRejectsNativeValue() external {
        uint256 aiId = _mintAI(ALICE, "PING");
        rewardToken.mint(address(holderVault), 9 ether);

        (bool pinged,) = address(holderVault).call("");
        assertTrue(pinged);
        assertEq(holderVault.claimable(aiId), 9 ether);

        vm.deal(address(this), 1 ether);
        (bool acceptedNative,) = address(holderVault).call{value: 1 ether}("");
        assertFalse(acceptedNative);
        assertEq(address(holderVault).balance, 0);
    }

    function testNativeBNBQuoteRewardsAIHolder() external {
        uint256 aiId = _mintAI(ALICE, "NATIVE");
        TinyAIHolderVault nativeVault = new TinyAIHolderVault(IERC20(address(0)), address(this));
        nativeVault.bindProtocol(address(protocol));
        vm.prank(address(protocol));
        nativeVault.registerAI(aiId);

        vm.deal(address(this), 12 ether);
        (bool deposited,) = address(nativeVault).call{value: 12 ether}("");
        assertTrue(deposited);
        assertTrue(nativeVault.isNativeReward());
        assertEq(nativeVault.claimable(aiId), 12 ether);

        uint256[] memory ids = new uint256[](1);
        ids[0] = aiId;
        uint256 aliceBefore = ALICE.balance;
        vm.prank(ALICE);
        nativeVault.claim(ids, ALICE);
        assertEq(ALICE.balance - aliceBefore, 12 ether);
        assertEq(nativeVault.totalClaimed(), 12 ether);
    }

    function testNewAIHasNoRetroactiveClaimOnEarlierTaxRevenue() external {
        vm.prank(BOB);
        token.approve(address(protocol), type(uint256).max);
        uint256 aliceAI = _mintAI(ALICE, "ALICE-1");
        uint256 bobAI = _mintAI(BOB, "BOB-1");
        rewardToken.mint(address(holderVault), 200 ether);

        uint256 aliceAI2 = _mintAI(ALICE, "ALICE-2");
        rewardToken.mint(address(holderVault), 300 ether);
        holderVault.sync();

        assertEq(holderVault.claimable(aliceAI), 200 ether);
        assertEq(holderVault.claimable(bobAI), 200 ether);
        assertEq(holderVault.claimable(aliceAI2), 100 ether);
    }

    function testRevenueBeforeFirstAIStaysUnallocated() external {
        rewardToken.mint(address(holderVault), 9 ether);
        holderVault.sync();
        assertEq(holderVault.unallocatedRewards(), 9 ether);

        uint256 aiId = _mintAI(ALICE, "FIRST");
        assertEq(holderVault.claimable(aiId), 0);

        rewardToken.mint(address(holderVault), 7 ether);
        holderVault.sync();
        assertEq(holderVault.claimable(aiId), 7 ether);
        assertEq(holderVault.unallocatedRewards(), 9 ether);
    }

    function testClaimPreservesFractionalCarry() external {
        vm.prank(BOB);
        token.approve(address(protocol), type(uint256).max);
        uint256 aliceAI = _mintAI(ALICE, "FRACTION-A");
        uint256 bobAI = _mintAI(BOB, "FRACTION-B");
        uint256 aliceAI2 = _mintAI(ALICE, "FRACTION-C");

        rewardToken.mint(address(holderVault), 5);
        holderVault.sync();
        uint256[] memory first = new uint256[](1);
        first[0] = aliceAI;
        vm.prank(ALICE);
        holderVault.claim(first, ALICE);
        assertEq(rewardToken.balanceOf(ALICE), 1);

        rewardToken.mint(address(holderVault), 2);
        holderVault.sync();
        assertEq(holderVault.claimable(aliceAI), 1);
        assertEq(holderVault.claimable(bobAI), 2);
        assertEq(holderVault.claimable(aliceAI2), 2);
    }

    function testRepeatedSyncCannotRedistributeTheSameRoundingRemainder() external {
        vm.prank(BOB);
        token.approve(address(protocol), type(uint256).max);
        uint256 aliceAI = _mintAI(ALICE, "ROUND-A");
        uint256 bobAI = _mintAI(BOB, "ROUND-B");
        uint256 aliceAI2 = _mintAI(ALICE, "ROUND-C");

        rewardToken.mint(address(holderVault), 1);
        holderVault.sync();
        uint256 checkpoint = holderVault.accumulatedRewardPerAI();
        assertEq(holderVault.pendingRewards(), 0);

        for (uint256 i; i < 8; ++i) {
            holderVault.sync();
        }
        assertEq(holderVault.accumulatedRewardPerAI(), checkpoint);
        assertEq(holderVault.claimable(aliceAI), 0);
        assertEq(holderVault.claimable(bobAI), 0);
        assertEq(holderVault.claimable(aliceAI2), 0);

        rewardToken.mint(address(holderVault), 3);
        holderVault.sync();
        assertEq(holderVault.claimable(aliceAI), 1);
        assertEq(holderVault.claimable(bobAI), 1);
        assertEq(holderVault.claimable(aliceAI2), 1);
    }

    function testUnclaimedRewardsFollowAIOnTransfer() external {
        uint256 aiId = _mintAI(ALICE, "TRANSFER-ME");
        rewardToken.mint(address(holderVault), 50 ether);
        holderVault.sync();

        vm.prank(ALICE);
        protocol.transferFrom(ALICE, BOB, aiId);

        uint256[] memory ids = new uint256[](1);
        ids[0] = aiId;
        vm.prank(BOB);
        holderVault.claim(ids, BOB);
        assertEq(rewardToken.balanceOf(BOB), 50 ether);
    }

    function testOnlyProtocolCanRegisterAIAndRewardTokenCannotBeWithdrawnByAdmin() external {
        vm.expectRevert(TinyAIHolderVault.OnlyProtocol.selector);
        holderVault.registerAI(1);

        (bool ok,) = address(holderVault)
            .call(abi.encodeWithSignature("withdraw(address,uint256)", address(rewardToken), 1 ether));
        assertFalse(ok);
    }

    function testFeeOnTransferTokenIsRejectedAtomically() external {
        TokenModeTaxToken taxed = new TokenModeTaxToken();
        taxed.mint(ALICE, 1_000_000 ether);
        TinyAITokenComponents taxedComponents =
            new TinyAITokenComponents("", address(this), TREASURY, taxed, COMPONENT_PRICE);
        taxedComponents.defineComponent(1, taxedComponents.EFFECT_MEMORY(), 0, 1, 100_000);
        taxedComponents.sealCatalog();

        vm.startPrank(ALICE);
        taxed.approve(address(taxedComponents), COMPONENT_PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExactERC20Payment.UnsupportedPaymentToken.selector,
                uint256(COMPONENT_PRICE),
                uint256(COMPONENT_PRICE) * 9 / 10
            )
        );
        taxedComponents.publicMint(1, 1);
        vm.stopPrank();

        assertEq(taxed.balanceOf(TREASURY), 0);
        assertEq(taxedComponents.totalMinted(), 0);
    }

    function testFeeOnTransferTokenCannotMintAI() external {
        TokenModeTaxToken taxed = new TokenModeTaxToken();
        taxed.mint(ALICE, 1_000_000 ether);
        TinyAITokenComponents taxedComponents =
            new TinyAITokenComponents("", address(this), TREASURY, taxed, COMPONENT_PRICE);
        TinyAIHolderVault taxedVault = new TinyAIHolderVault(rewardToken, address(this));
        TinyAITokenProtocol taxedProtocol =
            new TinyAITokenProtocol(registry, taxedComponents, taxedVault, address(this), TREASURY, taxed, AI_PRICE, 0);
        taxedVault.bindProtocol(address(taxedProtocol));
        taxedComponents.bindProtocol(address(taxedProtocol));

        vm.startPrank(ALICE);
        taxed.approve(address(taxedProtocol), AI_PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(ExactERC20Payment.UnsupportedPaymentToken.selector, AI_PRICE, AI_PRICE * 9 / 10)
        );
        taxedProtocol.mintAI("NO-TAX", bytes32("seed"), false);
        vm.stopPrank();

        assertEq(taxed.balanceOf(TREASURY), 0);
        assertEq(taxedProtocol.totalSupply(), 0);
    }

    function testNoHiddenSettlementOrFeeAdministration() external {
        (bool tokenSwapOk,) =
            address(protocol).call(abi.encodeWithSignature("setPaymentToken(address)", address(0x1234)));
        (bool marketFeeOk,) = address(market).call(abi.encodeWithSignature("setFee(uint16,address)", 100, TREASURY));
        assertFalse(tokenSwapOk);
        assertFalse(marketFeeOk);
        assertEq(address(protocol.paymentToken()), address(token));
        assertEq(address(components.paymentToken()), address(token));
        assertEq(address(market.paymentToken()), address(token));
    }

    function _mintAI(address owner, string memory name) private returns (uint256 aiId) {
        vm.prank(owner);
        aiId = protocol.mintAI(name, keccak256(bytes(name)), false);
    }

    function _defineCatalog(TinyAITokenComponents target) private {
        target.defineComponent(1, target.EFFECT_MEMORY(), 0, 1, 30_000);
        target.defineComponent(2, target.EFFECT_PERSONALITY(), 0, 5, 15_000);
        target.defineComponent(3, target.EFFECT_PERSONALITY(), 1, 5, 15_000);
        target.defineComponent(4, target.EFFECT_PERSONALITY(), 2, 5, 15_000);
        target.defineComponent(5, target.EFFECT_PERSONALITY(), 3, 5, 15_000);
        target.defineComponent(6, target.EFFECT_EXPRESSION(), 0, 1, 10_000);
        target.sealCatalog();
    }
}
