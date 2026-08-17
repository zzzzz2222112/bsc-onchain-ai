// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {TinyAIKnowledgeV4} from "../src/TinyAIKnowledgeV4.sol";
import {TinyAIReasonerV4} from "../src/TinyAIReasonerV4.sol";

/// @notice Deploys the immutable v4 knowledge renderer and its bounded reasoner.
contract DeployReasoningV4 is Script {
    function run() external returns (TinyAIKnowledgeV4 knowledge, TinyAIReasonerV4 reasoner) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        knowledge = new TinyAIKnowledgeV4();
        reasoner = new TinyAIReasonerV4(knowledge);
        vm.stopBroadcast();

        if (!reasoner.integrityOk()) revert TinyAIReasonerV4.InvalidKnowledge();

        console2.log("deployer", deployer);
        console2.log("knowledge", address(knowledge));
        console2.log("reasoner", address(reasoner));
        console2.logBytes32(reasoner.KNOWLEDGE_HASH());
        console2.logBytes32(reasoner.knowledgeCodeHash());
    }
}
