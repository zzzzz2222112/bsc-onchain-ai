// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {FixedSupplyChatToken} from "../src/FixedSupplyChatToken.sol";
import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIModelCard} from "../src/TinyAIModelCard.sol";

contract Deploy is Script {
    function run() external returns (TinyAIChat chat, TinyAIModelCard model, IERC20 token) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }
        address treasury = vm.envOr("TREASURY", deployer);
        address liquidity = vm.envOr("LIQUIDITY_RECIPIENT", deployer);
        address community = vm.envOr("COMMUNITY_RECIPIENT", deployer);
        uint256 feePerChat = vm.envOr("FEE_PER_CHAT", uint256(10 ether));
        uint16 burnBps = uint16(vm.envOr("BURN_BPS", uint256(2_500)));
        bool deployToken = vm.envOr("DEPLOY_TOKEN", true);
        string memory tokenName = vm.envOr("TOKEN_NAME", string("TinyAI Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("TAI"));
        bytes32 corpusSha256 = vm.parseBytes32(string.concat("0x", _trim(vm.readFile("../model/build/corpus.sha256"))));

        bytes memory zhLexicon = vm.readFileBinary("../model/build/lexicon-zh.bin");
        bytes memory enLexicon = vm.readFileBinary("../model/build/lexicon-en.bin");

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        address[22] memory weightsBlobs;
        for (uint256 index; index < weightsBlobs.length; ++index) {
            bytes memory weightChunk =
                vm.readFileBinary(string.concat("../model/build/model-", vm.toString(index), ".bin"));
            weightsBlobs[index] = address(new BytecodeBlob(weightChunk));
        }
        address zhLexiconBlob = address(new BytecodeBlob(zhLexicon));
        address enLexiconBlob = address(new BytecodeBlob(enLexicon));
        model = new TinyAIModelCard(weightsBlobs, zhLexiconBlob, enLexiconBlob, corpusSha256);

        if (deployToken) {
            token = IERC20(address(new FixedSupplyChatToken(tokenName, tokenSymbol, treasury, liquidity, community)));
        } else {
            token = IERC20(vm.envAddress("PAYMENT_TOKEN"));
        }
        chat = new TinyAIChat(model, token, treasury, feePerChat, burnBps);
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        for (uint256 index; index < weightsBlobs.length; ++index) {
            console2.log(string.concat("weightsBlob", vm.toString(index)), weightsBlobs[index]);
        }
        console2.log("zhLexiconBlob", zhLexiconBlob);
        console2.log("enLexiconBlob", enLexiconBlob);
        console2.log("modelCard", address(model));
        console2.log("paymentToken", address(token));
        console2.log("chat", address(chat));
        console2.log("feePerChat", feePerChat);
        console2.log("burnBps", burnBps);
    }

    function _trim(string memory value) private pure returns (string memory) {
        bytes memory raw = bytes(value);
        uint256 length = raw.length;
        while (length != 0 && (raw[length - 1] == 0x0A || raw[length - 1] == 0x0D || raw[length - 1] == 0x20)) {
            length -= 1;
        }
        bytes memory output = new bytes(length);
        for (uint256 i; i < length; ++i) {
            output[i] = raw[i];
        }
        return string(output);
    }
}
