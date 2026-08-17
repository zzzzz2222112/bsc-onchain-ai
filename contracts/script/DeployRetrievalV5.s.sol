// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {TinyAIChat} from "../src/TinyAIChat.sol";
import {TinyAIKnowledgeV5} from "../src/TinyAIKnowledgeV5.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";

/// @notice Adds the immutable v5 knowledge and retrieval layers to an existing v3 classifier.
contract DeployRetrievalV5 is Script {
    function run() external returns (TinyAIKnowledgeV5 knowledge, TinyAIRetrieverV5 retriever) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }
        TinyAIChat classifier = TinyAIChat(vm.envAddress("CLASSIFIER"));

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        knowledge = new TinyAIKnowledgeV5();
        retriever = new TinyAIRetrieverV5(classifier, knowledge);
        vm.stopBroadcast();

        if (!retriever.integrityOk()) revert TinyAIRetrieverV5.InvalidKnowledge();
        console2.log("deployer", deployer);
        console2.log("classifier", address(classifier));
        console2.log("knowledge", address(knowledge));
        console2.log("retriever", address(retriever));
        console2.logBytes32(retriever.KNOWLEDGE_HASH());
    }
}
