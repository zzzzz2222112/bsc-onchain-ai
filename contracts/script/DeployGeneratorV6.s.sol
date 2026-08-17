// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

import {BytecodeBlob} from "../src/BytecodeBlob.sol";
import {TinyAIGeneratorV6} from "../src/TinyAIGeneratorV6.sol";
import {TinyAIRetrieverV5} from "../src/TinyAIRetrieverV5.sol";

/// @notice Adds the immutable v6 neural generator to an existing v5 retriever.
contract DeployGeneratorV6 is Script {
    function run() external returns (BytecodeBlob modelBlob, BytecodeBlob lexiconBlob, TinyAIGeneratorV6 generator) {
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }
        TinyAIRetrieverV5 retriever = TinyAIRetrieverV5(vm.envAddress("RETRIEVER"));
        bytes memory model = vm.readFileBinary("../model/build/generator-v6-model.bin");
        bytes memory lexicon = vm.readFileBinary("../model/build/generator-v6-lexicon.bin");

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        modelBlob = new BytecodeBlob(model);
        lexiconBlob = new BytecodeBlob(lexicon);
        generator = new TinyAIGeneratorV6(retriever, address(modelBlob), address(lexiconBlob));
        vm.stopBroadcast();

        if (!generator.integrityOk()) revert TinyAIGeneratorV6.InvalidModel();
        console2.log("deployer", deployer);
        console2.log("retriever", address(retriever));
        console2.log("modelBlob", address(modelBlob));
        console2.log("lexiconBlob", address(lexiconBlob));
        console2.log("generator", address(generator));
        console2.logBytes32(generator.MODEL_SHA256());
        console2.logBytes32(generator.LEXICON_SHA256());
    }
}
