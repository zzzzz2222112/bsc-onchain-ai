// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TinyAIGeneratorV6} from "../TinyAIGeneratorV6.sol";
import {TinyAIRetrieverV5} from "../TinyAIRetrieverV5.sol";

import {IBrainEngine} from "./IBrainEngine.sol";

/// @notice Protocol adapter that turns the immutable TinyAI v6 model into Genesis Brain V1.
contract TinyAIV6BrainEngine is IBrainEngine {
    uint32 public constant PROTOCOL_VERSION = 1;

    uint64 private constant CUE_ADMIN = uint64(1) << 2;
    uint64 private constant CUE_MINT = uint64(1) << 3;
    uint64 private constant CUE_PROXY = uint64(1) << 4;
    uint8 private constant NO_NEURAL_CONTEXT = type(uint8).max;

    TinyAIGeneratorV6 public immutable generator;
    bytes32 public immutable generatorCodeHash;

    error InvalidGenerator();

    constructor(TinyAIGeneratorV6 generator_) {
        if (address(generator_).code.length == 0 || !generator_.integrityOk()) revert InvalidGenerator();
        generator = generator_;
        generatorCodeHash = address(generator_).codehash;
    }

    function engineVersion() external pure returns (uint32) {
        return PROTOCOL_VERSION;
    }

    function truthBoundary() external pure returns (string memory) {
        return "off-chain training; v5 routing, v6 int8 generation, AI DNA variant choice, trace and final response execute in EVM";
    }

    function integrityOk() external view returns (bool) {
        return address(generator).codehash == generatorCodeHash && generator.integrityOk();
    }

    function infer(BrainInput calldata input) external view returns (BrainOutput memory output) {
        TinyAIRetrieverV5.RetrievalResult memory base = generator.retriever().preview(address(0), input.prompt);
        (uint8 context, bool supported) = _neuralContext(base);
        bool useNeural = supported && base.chinese && !base.unknown;
        uint8 unlockedVariants = 2 + (input.expressionLevel > 2 ? 2 : input.expressionLevel);
        uint8 variant = uint8(
            uint256(
                keccak256(
                    abi.encode(
                        input.dna,
                        keccak256(bytes(input.prompt)),
                        input.curiosity,
                        input.empathy,
                        input.humor,
                        input.caution,
                        input.skillMask,
                        input.turns,
                        input.memoryRoot,
                        input.speaker
                    )
                )
            ) % unlockedVariants
        );

        bytes32 generationTrace;
        string memory response = base.response;
        if (useNeural) {
            TinyAIGeneratorV6.NeuralOutput memory neural = generator.generateFromContext(context, variant);
            response = neural.response;
            generationTrace = neural.traceHash;
        } else {
            context = NO_NEURAL_CONTEXT;
            variant = 0;
            generationTrace = keccak256(abi.encode("TinyAI-protocol-v1-fallback", base.traceHash, base.unknown));
        }

        output = BrainOutput({
            response: response,
            confidence: base.matchScore,
            topic: base.topic,
            variant: variant,
            unknown: base.unknown,
            neuralGenerated: useNeural,
            traceHash: keccak256(
                abi.encode(
                    PROTOCOL_VERSION,
                    generatorCodeHash,
                    base.traceHash,
                    generationTrace,
                    input.aiId,
                    input.dna,
                    input.memoryRoot,
                    context,
                    variant
                )
            )
        });
    }

    function _neuralContext(TinyAIRetrieverV5.RetrievalResult memory base)
        private
        pure
        returns (uint8 context, bool supported)
    {
        if (base.topic == 1) return (0, true);
        if (base.topic == 3) return (1, true);
        if (base.topic == 4) return (2, true);
        if (base.topic == 5) return (3, true);
        if (base.topic == 7 && !base.negated) {
            if ((base.cues & CUE_MINT) != 0 && (base.cues & CUE_ADMIN) != 0) return (4, true);
            if ((base.cues & CUE_PROXY) != 0 && (base.cues & CUE_ADMIN) != 0) return (5, true);
        }
        return (NO_NEURAL_CONTEXT, false);
    }
}
