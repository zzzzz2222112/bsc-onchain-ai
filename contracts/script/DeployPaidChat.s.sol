// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {FixedSupplyChatToken} from "../src/FixedSupplyChatToken.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";

/// @notice Attaches token payments to an existing immutable TinyAI model card.
/// @dev This deliberately avoids redeploying the twenty-two model blobs and two lexicons.
contract DeployPaidChat is Script {
    error InvalidPaidConfiguration();
    error InvalidModelCard();

    function run() external returns (TinyAIChat chat, IERC20 token) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        TinyAIModelCard model = TinyAIModelCard(vm.envAddress("MODEL_CARD"));
        if (address(model).code.length == 0 || !model.integrityOk()) revert InvalidModelCard();

        address treasury = vm.envOr("TREASURY", deployer);
        address liquidity = vm.envOr("LIQUIDITY_RECIPIENT", deployer);
        address community = vm.envOr("COMMUNITY_RECIPIENT", deployer);
        uint256 feePerChat = vm.envOr("FEE_PER_CHAT", uint256(10 ether));
        uint256 burnBpsRaw = vm.envOr("BURN_BPS", uint256(2_500));
        bool deployToken = vm.envOr("DEPLOY_TOKEN", true);
        string memory tokenName = vm.envOr("TOKEN_NAME", string("TinyAI Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("TAI"));

        if (treasury == address(0) || feePerChat == 0 || burnBpsRaw > 10_000) {
            revert InvalidPaidConfiguration();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 burnBps = uint16(burnBpsRaw); // The explicit 10,000 bound above is below uint16.max.

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        if (deployToken) {
            token = IERC20(address(new FixedSupplyChatToken(tokenName, tokenSymbol, treasury, liquidity, community)));
        } else {
            token = IERC20(vm.envAddress("PAYMENT_TOKEN"));
            if (address(token).code.length == 0) revert InvalidPaidConfiguration();
        }
        chat = new TinyAIChat(model, token, treasury, feePerChat, burnBps);
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("reusedModelCard", address(model));
        console2.log("paymentToken", address(token));
        console2.log("paidChat", address(chat));
        console2.log("treasury", treasury);
        console2.log("feePerChat", feePerChat);
        console2.log("burnBps", burnBpsRaw);
    }
}
