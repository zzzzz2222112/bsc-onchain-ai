// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IBrainEngine {
    struct BrainInput {
        uint256 aiId;
        bytes32 dna;
        uint8 curiosity;
        uint8 empathy;
        uint8 humor;
        uint8 caution;
        uint8 expressionLevel;
        uint64 skillMask;
        uint32 turns;
        bytes32 memoryRoot;
        address speaker;
        string prompt;
    }

    struct BrainOutput {
        string response;
        uint16 confidence;
        uint8 topic;
        uint8 variant;
        bool unknown;
        bool neuralGenerated;
        bytes32 traceHash;
    }

    function engineVersion() external view returns (uint32);
    function infer(BrainInput calldata input) external view returns (BrainOutput memory output);
    function integrityOk() external view returns (bool);
    function truthBoundary() external pure returns (string memory);
}
