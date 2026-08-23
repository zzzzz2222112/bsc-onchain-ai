// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {TinyAIBrainRegistry} from "../src/protocol/TinyAIBrainRegistry.sol";
import {TinyAIHolderVault} from "../src/protocol/TinyAIHolderVault.sol";
import {TinyAITokenComponents} from "../src/protocol/TinyAITokenComponents.sol";
import {TinyAITokenMarket} from "../src/protocol/TinyAITokenMarket.sol";
import {TinyAITokenProtocol} from "../src/protocol/TinyAITokenProtocol.sol";

/// @notice Step 3: predeploys the ERC-20-settled TinyAI stack against a CREATE2-predicted Flap CA.
/// @dev The holder Vault and predicted CA are bound while the token address is still empty.
///      Nothing is broadcast unless Forge receives --broadcast.
contract DeployTokenProtocol is Script {
    uint256 private constant BSC_CHAIN_ID = 56;
    address private constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    uint256 private constant TOKEN_MINT_PRICE = 500 ether;

    uint256 private constant MEMORY_CELL = 1;
    uint256 private constant CURIOSITY_GENE = 2;
    uint256 private constant EMPATHY_GENE = 3;
    uint256 private constant HUMOR_GENE = 4;
    uint256 private constant CAUTION_GENE = 5;
    uint256 private constant EXPRESSION_CORE = 6;

    struct DeploymentConfig {
        bool cliSigner;
        uint256 privateKey;
        address deployer;
        address finalOwner;
        address treasury;
        IERC20 token;
        TinyAIHolderVault holderVault;
        TinyAIBrainRegistry registry;
        uint256 aiMintPrice;
        uint128 componentMintPrice;
        uint256 chatPrice;
        string componentUri;
    }

    struct DeploymentResult {
        TinyAITokenComponents components;
        TinyAITokenProtocol protocol;
        TinyAITokenMarket market;
    }

    function run() external {
        require(block.chainid == BSC_CHAIN_ID, "BSC_CHAIN_ID_REQUIRED");
        DeploymentConfig memory config = _loadConfig();
        _validateConfig(config);
        DeploymentResult memory result = _deploy(config);
        _logDeployment(config, result);
        console2.log("next: launch the reserved Flap salt and require the returned token to match payment token");
    }

    function _loadConfig() private view returns (DeploymentConfig memory config) {
        config.cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        if (config.cliSigner) {
            config.deployer = vm.envAddress("DEPLOYER");
        } else {
            config.privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            config.deployer = vm.addr(config.privateKey);
        }

        config.finalOwner = vm.envOr("PROTOCOL_OWNER", config.deployer);
        config.treasury = vm.envOr("TREASURY", config.finalOwner);
        config.token = IERC20(vm.envAddress("PAYMENT_TOKEN"));
        config.holderVault = TinyAIHolderVault(payable(vm.envAddress("HOLDER_VAULT")));
        config.registry = TinyAIBrainRegistry(vm.envAddress("BRAIN_REGISTRY"));
        config.aiMintPrice = vm.envOr("AI_MINT_PRICE", TOKEN_MINT_PRICE);
        uint256 componentMintPrice = vm.envOr("COMPONENT_MINT_PRICE", TOKEN_MINT_PRICE);
        require(componentMintPrice <= type(uint128).max, "COMPONENT_MINT_PRICE_OVERFLOW");
        config.componentMintPrice = uint128(componentMintPrice);
        config.chatPrice = vm.envOr("CHAT_PRICE", uint256(0));
        config.componentUri = vm.envOr("COMPONENT_BASE_URI", string("ipfs://tinyai-token/{id}.json"));
    }

    function _validateConfig(DeploymentConfig memory config) private view {
        address token = address(config.token);
        address rewardToken = address(config.holderVault.rewardToken());

        require(token != address(0), "INVALID_PAYMENT_TOKEN");
        require(token.code.length == 0, "PREDICTED_PAYMENT_TOKEN_MUST_BE_EMPTY");
        require(uint160(token) & 0xffff == 0x7777, "PREDICTED_TOKEN_MUST_END_7777");
        require(address(config.holderVault).code.length > 0, "INVALID_HOLDER_VAULT");
        require(rewardToken == NVDAB && rewardToken.code.length > 0, "FLAP_REWARD_TOKEN_MUST_BE_NVDAB");
        require(config.holderVault.protocol() == address(0), "HOLDER_VAULT_ALREADY_BOUND");
        require(config.holderVault.owner() == config.deployer, "DEPLOYER_MUST_OWN_HOLDER_VAULT");
        require(config.aiMintPrice == TOKEN_MINT_PRICE, "AI_MINT_PRICE_MUST_BE_500_TOKENS");
        require(config.componentMintPrice == TOKEN_MINT_PRICE, "COMPONENT_MINT_PRICE_MUST_BE_500_TOKENS");
        require(config.chatPrice == 0, "CHAT_MUST_REMAIN_FREE");

        uint32 recommendedVersion = config.registry.recommendedVersion();
        require(recommendedVersion != 0 && config.registry.upgradeEnabled(recommendedVersion), "INVALID_RECOMMENDED_BRAIN");
        config.registry.engineFor(recommendedVersion);
    }

    function _deploy(DeploymentConfig memory config) private returns (DeploymentResult memory result) {
        if (config.cliSigner) vm.startBroadcast();
        else vm.startBroadcast(config.privateKey);

        result.components = new TinyAITokenComponents(
            config.componentUri, config.deployer, config.treasury, config.token, config.componentMintPrice
        );
        result.protocol = new TinyAITokenProtocol(
            config.registry,
            result.components,
            config.holderVault,
            config.deployer,
            config.treasury,
            config.token,
            config.aiMintPrice,
            config.chatPrice
        );
        config.holderVault.bindProtocol(address(result.protocol));
        result.components.bindProtocol(address(result.protocol));
        result.market = new TinyAITokenMarket(address(result.protocol), address(result.components), config.token);
        _defineGenesisComponents(result.components);
        result.components.sealCatalog();

        if (config.finalOwner != config.deployer) {
            config.holderVault.transferOwnership(config.finalOwner);
            result.components.transferOwnership(config.finalOwner);
            result.protocol.transferOwnership(config.finalOwner);
        }
        vm.stopBroadcast();
    }

    function _logDeployment(DeploymentConfig memory config, DeploymentResult memory result) private view {
        console2.log("deployer", config.deployer);
        console2.log("pending/final owner", config.finalOwner);
        console2.log("treasury", config.treasury);
        console2.log("payment token", address(config.token));
        console2.log("predicted future Flap payment token", address(config.token));
        console2.log("Flap quote/reward asset", address(config.holderVault.rewardToken()));
        console2.log("AI holder reward vault", address(config.holderVault));
        console2.log("brain registry", address(config.registry));
        console2.log("token components", address(result.components));
        console2.log("token AI protocol", address(result.protocol));
        console2.log("token market", address(result.market));
        console2.log("AI mint price", config.aiMintPrice);
        console2.log("component mint price", config.componentMintPrice);
        console2.log("chat price", config.chatPrice);
    }

    function _defineGenesisComponents(TinyAITokenComponents components) private {
        components.defineComponent(MEMORY_CELL, components.EFFECT_MEMORY(), 0, 1, 30_000);
        components.defineComponent(CURIOSITY_GENE, components.EFFECT_PERSONALITY(), 0, 5, 15_000);
        components.defineComponent(EMPATHY_GENE, components.EFFECT_PERSONALITY(), 1, 5, 15_000);
        components.defineComponent(HUMOR_GENE, components.EFFECT_PERSONALITY(), 2, 5, 15_000);
        components.defineComponent(CAUTION_GENE, components.EFFECT_PERSONALITY(), 3, 5, 15_000);
        components.defineComponent(EXPRESSION_CORE, components.EFFECT_EXPRESSION(), 0, 1, 10_000);
    }
}
