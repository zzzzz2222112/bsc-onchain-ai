// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TinyAIRetrieverV5} from "../TinyAIRetrieverV5.sol";

import {IBrainEngine} from "./IBrainEngine.sol";
import {TinyAINeuralDecoderV2} from "./TinyAINeuralDecoderV2.sol";

/// @notice Brain V2 keeps Genesis Brain V1 semantics while fitting BSC's transaction gas ceiling.
contract TinyAIBrainEngineV2 is IBrainEngine {
    uint32 public constant PROTOCOL_VERSION = 2;

    uint64 private constant CUE_ADMIN = uint64(1) << 2;
    uint64 private constant CUE_MINT = uint64(1) << 3;
    uint64 private constant CUE_PROXY = uint64(1) << 4;
    uint8 private constant NO_NEURAL_CONTEXT = type(uint8).max;

    TinyAIRetrieverV5 public immutable retriever;
    TinyAINeuralDecoderV2 public immutable decoder;
    bytes32 public immutable retrieverCodeHash;
    bytes32 public immutable decoderCodeHash;

    error InvalidRetriever();
    error InvalidDecoder();

    constructor(TinyAIRetrieverV5 retriever_, TinyAINeuralDecoderV2 decoder_) {
        if (address(retriever_).code.length == 0 || retriever_.VERSION() != 5 || !retriever_.integrityOk()) {
            revert InvalidRetriever();
        }
        if (address(decoder_).code.length == 0 || decoder_.VERSION() != 2 || !decoder_.integrityOk()) {
            revert InvalidDecoder();
        }
        retriever = retriever_;
        decoder = decoder_;
        retrieverCodeHash = address(retriever_).codehash;
        decoderCodeHash = address(decoder_).codehash;
    }

    function engineVersion() external pure returns (uint32) {
        return PROTOCOL_VERSION;
    }

    function truthBoundary() external pure returns (string memory) {
        return "off-chain training; v5 retrieval, complete v6 int8 neural matrix inference, AI DNA variant selection, trace and response execute in EVM";
    }

    function integrityOk() external view returns (bool) {
        return address(retriever).codehash == retrieverCodeHash && address(decoder).codehash == decoderCodeHash
            && retriever.integrityOk() && decoder.integrityOk();
    }

    function infer(BrainInput calldata input) external view returns (BrainOutput memory output) {
        TinyAIRetrieverV5.RetrievalResult memory base = retriever.preview(address(0), input.prompt);
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
            TinyAINeuralDecoderV2.NeuralOutput memory neural = decoder.generateFromContext(context, variant);
            response = neural.response;
            generationTrace = neural.traceHash;
        } else {
            context = NO_NEURAL_CONTEXT;
            variant = 0;
            generationTrace = keccak256(abi.encode("TinyAI-protocol-v2-fallback", base.traceHash, base.unknown));
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
                    retrieverCodeHash,
                    decoderCodeHash,
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
