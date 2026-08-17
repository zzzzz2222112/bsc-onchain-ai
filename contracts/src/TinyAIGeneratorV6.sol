// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TinyAIRetrieverV5} from "./TinyAIRetrieverV5.sol";

/// @notice TinyAI v6: v5-grounded, token-by-token neural generation in the EVM.
/// @dev Training is off-chain. Every quantized hidden activation, vocabulary score,
///      greedy token choice, lexicon read, trace commitment, and final byte executes here.
contract TinyAIGeneratorV6 {
    uint8 public constant VERSION = 6;
    uint8 public constant NEURAL_CONTEXTS = 6;
    uint8 public constant VARIANTS = 4;
    uint8 public constant CONTEXT_KEYS = 24;
    uint8 public constant VOCABULARY_TOKENS = 133;
    uint8 public constant HIDDEN_UNITS = 32;
    uint8 public constant MAX_GENERATED_TOKENS = 16;
    uint8 public constant ACTIVATION_LIMIT = 8;
    uint16 public constant MODEL_BYTES = 10_074;
    uint16 public constant LEXICON_BYTES = 2_137;
    uint16 public constant MAX_RESPONSE_BYTES = 512;

    bytes32 public constant MODEL_SHA256 = 0x0a7dd9d4cecc5b099fa612c6c8da0420b3ccf6db0494193c74d681e2d173185a;
    bytes32 public constant LEXICON_SHA256 = 0xb88b337ab3be2e1ee25f4e4e21a5deceeb92cffd72fbe07e64a617add39ffd6d;
    bytes32 public constant CORPUS_SHA256 = 0x6d5a2b8d62215ccfe4db5a4886aeff9718f643a72c9d36a413fd13db80493743;

    uint8 public constant CONTEXT_IDENTITY = 0;
    uint8 public constant CONTEXT_BSC = 1;
    uint8 public constant CONTEXT_HUMAN = 2;
    uint8 public constant CONTEXT_GAS = 3;
    uint8 public constant CONTEXT_MINT_RISK = 4;
    uint8 public constant CONTEXT_PROXY_RISK = 5;
    uint8 public constant NO_NEURAL_CONTEXT = type(uint8).max;

    uint8 private constant TOKEN_BOS = 0;
    uint8 private constant TOKEN_EOS = 1;
    uint256 private constant MODEL_HEADER_BYTES = 16;
    uint256 private constant CONTEXT_EMBEDDINGS_OFFSET = MODEL_HEADER_BYTES;
    uint256 private constant TOKEN_EMBEDDINGS_OFFSET =
        CONTEXT_EMBEDDINGS_OFFSET + uint256(CONTEXT_KEYS) * uint256(HIDDEN_UNITS);
    uint256 private constant POSITION_EMBEDDINGS_OFFSET =
        TOKEN_EMBEDDINGS_OFFSET + uint256(VOCABULARY_TOKENS) * uint256(HIDDEN_UNITS);
    uint256 private constant OUTPUT_WEIGHTS_OFFSET =
        POSITION_EMBEDDINGS_OFFSET + uint256(MAX_GENERATED_TOKENS) * uint256(HIDDEN_UNITS);
    uint256 private constant OUTPUT_BIAS_OFFSET =
        OUTPUT_WEIGHTS_OFFSET + uint256(VOCABULARY_TOKENS) * uint256(HIDDEN_UNITS);
    uint256 private constant LEXICON_OFFSETS_OFFSET = 8;
    uint256 private constant LEXICON_DATA_OFFSET = LEXICON_OFFSETS_OFFSET + (uint256(VOCABULARY_TOKENS) + 1) * 2;

    uint64 private constant CUE_ADMIN = uint64(1) << 2;
    uint64 private constant CUE_MINT = uint64(1) << 3;
    uint64 private constant CUE_PROXY = uint64(1) << 4;

    struct Memory {
        uint32 turns;
        uint8 lastTopic;
        uint8 lastNeuralContext;
        uint8 lastTokenCount;
        bytes32 rollingContext;
    }

    struct NeuralOutput {
        string response;
        uint8 context;
        uint8 variant;
        uint8 tokenCount;
        uint8 stepCount;
        uint8[16] tokenIds;
        int32[16] tokenScores;
        bytes32 traceHash;
    }

    struct GenerationResult {
        string response;
        string evidence;
        uint8 topic;
        uint8 queryType;
        uint8 neuralContext;
        uint8 variant;
        uint8 tokenCount;
        uint8 stepCount;
        uint8[16] tokenIds;
        int32[16] tokenScores;
        uint16 classifierConfidence;
        uint16 matchScore;
        uint16[3] factIds;
        uint8 factCount;
        bool neuralGenerated;
        bool unknown;
        bool negated;
        bytes32 retrievalTraceHash;
        bytes32 generationTraceHash;
        bytes32 nextContext;
    }

    TinyAIRetrieverV5 public immutable retriever;
    address public immutable modelBlob;
    address public immutable lexiconBlob;
    bytes32 public immutable retrieverCodeHash;
    bytes32 public immutable modelCodeHash;
    bytes32 public immutable lexiconCodeHash;
    uint64 public totalChats;

    mapping(address user => Memory memoryState) private _memories;

    event GeneratedChat(
        address indexed user,
        uint32 indexed turn,
        uint8 indexed topic,
        uint8 neuralContext,
        uint8 variant,
        uint8 tokenCount,
        uint8 stepCount,
        uint8[16] tokenIds,
        int32[16] tokenScores,
        uint16[3] factIds,
        uint8 factCount,
        bool neuralGenerated,
        bool unknown,
        string prompt,
        string response,
        string evidence,
        bytes32 retrievalTraceHash,
        bytes32 generationTraceHash,
        bytes32 contextHash
    );

    error InvalidRetriever();
    error InvalidModel();
    error InvalidLexicon();
    error InvalidNeuralContext(uint8 context);
    error InvalidVariant(uint8 variant);

    constructor(TinyAIRetrieverV5 retriever_, address modelBlob_, address lexiconBlob_) {
        if (address(retriever_).code.length == 0 || retriever_.VERSION() != 5 || !retriever_.integrityOk()) {
            revert InvalidRetriever();
        }
        bytes memory model = _payload(modelBlob_, MODEL_BYTES, false);
        if (
            _bytes4(model, 0) != bytes4("TAG6") || uint8(model[4]) != VERSION || uint8(model[5]) != CONTEXT_KEYS
                || uint8(model[6]) != VOCABULARY_TOKENS || uint8(model[7]) != HIDDEN_UNITS
                || uint8(model[8]) != MAX_GENERATED_TOKENS || uint8(model[9]) != ACTIVATION_LIMIT
                || sha256(model) != MODEL_SHA256
        ) revert InvalidModel();

        bytes memory lexicon = _payload(lexiconBlob_, LEXICON_BYTES, true);
        if (
            _bytes4(lexicon, 0) != bytes4("TAL6") || uint8(lexicon[4]) != VERSION
                || uint8(lexicon[5]) != VOCABULARY_TOKENS || sha256(lexicon) != LEXICON_SHA256
        ) revert InvalidLexicon();

        retriever = retriever_;
        modelBlob = modelBlob_;
        lexiconBlob = lexiconBlob_;
        retrieverCodeHash = address(retriever_).codehash;
        modelCodeHash = modelBlob_.codehash;
        lexiconCodeHash = lexiconBlob_.codehash;
    }

    function architecture() external pure returns (string memory) {
        return "v5 trained retrieval -> int8 context/previous-token/position embeddings -> hard-tanh -> trained vocabulary head -> greedy token decode";
    }

    function truthBoundary() external pure returns (string memory) {
        return "training and token authoring off-chain; every hidden activation, vocabulary score, token choice, UTF-8 lookup, trace, and final generated byte on-chain";
    }

    function capacityBoundary() external pure returns (string memory) {
        return "24 authored training sequences across six neural contexts; exact reconstruction is not open-world language understanding; unsupported topics retain v5";
    }

    function memoryOf(address user) external view returns (Memory memory) {
        return _memories[user];
    }

    function integrityOk() external view returns (bool) {
        return address(retriever).codehash == retrieverCodeHash && modelBlob.codehash == modelCodeHash
            && lexiconBlob.codehash == lexiconCodeHash && retriever.integrityOk();
    }

    function generateFromContext(uint8 context, uint8 variant) external view returns (NeuralOutput memory) {
        if (context >= NEURAL_CONTEXTS) revert InvalidNeuralContext(context);
        if (variant >= VARIANTS) revert InvalidVariant(variant);
        return _generate(context, variant);
    }

    function preview(address user, string calldata prompt) external view returns (GenerationResult memory) {
        return _reason(user, prompt, _memories[user]);
    }

    function chat(string calldata prompt) external returns (GenerationResult memory result) {
        Memory memory prior = _memories[msg.sender];
        result = _reason(msg.sender, prompt, prior);
        uint32 turn = prior.turns + 1;
        _memories[msg.sender] = Memory({
            turns: turn,
            lastTopic: result.topic,
            lastNeuralContext: result.neuralContext,
            lastTokenCount: result.tokenCount,
            rollingContext: result.nextContext
        });
        totalChats += 1;
        emit GeneratedChat(
            msg.sender,
            turn,
            result.topic,
            result.neuralContext,
            result.variant,
            result.tokenCount,
            result.stepCount,
            result.tokenIds,
            result.tokenScores,
            result.factIds,
            result.factCount,
            result.neuralGenerated,
            result.unknown,
            prompt,
            result.response,
            result.evidence,
            result.retrievalTraceHash,
            result.generationTraceHash,
            result.nextContext
        );
    }

    function _reason(address user, string calldata prompt, Memory memory prior)
        private
        view
        returns (GenerationResult memory result)
    {
        TinyAIRetrieverV5.RetrievalResult memory base = retriever.preview(address(0), prompt);
        (uint8 context, bool supported) = _neuralContext(base);
        bool usableNeuralContext = supported && base.chinese && !base.unknown;
        uint8 variant = uint8(uint256(keccak256(bytes(prompt))) & 3);

        result.evidence = base.evidence;
        result.topic = base.topic;
        result.queryType = base.queryType;
        result.neuralContext = usableNeuralContext ? context : NO_NEURAL_CONTEXT;
        result.variant = variant;
        result.classifierConfidence = base.classifierConfidence;
        result.matchScore = base.matchScore;
        result.factIds = base.factIds;
        result.factCount = base.factCount;
        result.unknown = base.unknown;
        result.negated = base.negated;
        result.retrievalTraceHash = base.traceHash;

        if (usableNeuralContext) {
            NeuralOutput memory neural = _generate(context, variant);
            result.response = neural.response;
            result.tokenCount = neural.tokenCount;
            result.stepCount = neural.stepCount;
            result.tokenIds = neural.tokenIds;
            result.tokenScores = neural.tokenScores;
            result.generationTraceHash = neural.traceHash;
            result.neuralGenerated = true;
        } else {
            result.response = base.response;
            result.generationTraceHash =
                keccak256(abi.encode("TinyAI-v6-v5-fallback", base.traceHash, base.topic, base.factIds, base.unknown));
        }

        result.nextContext = keccak256(
            abi.encode(
                prior.rollingContext,
                user,
                keccak256(bytes(prompt)),
                keccak256(bytes(result.response)),
                result.topic,
                result.neuralContext,
                result.variant,
                result.generationTraceHash
            )
        );
    }

    function _neuralContext(TinyAIRetrieverV5.RetrievalResult memory base)
        private
        pure
        returns (uint8 context, bool supported)
    {
        if (base.topic == 1) return (CONTEXT_IDENTITY, true);
        if (base.topic == 3) return (CONTEXT_BSC, true);
        if (base.topic == 4) return (CONTEXT_HUMAN, true);
        if (base.topic == 5) return (CONTEXT_GAS, true);
        if (base.topic == 7 && !base.negated) {
            if ((base.cues & CUE_MINT) != 0 && (base.cues & CUE_ADMIN) != 0) {
                return (CONTEXT_MINT_RISK, true);
            }
            if ((base.cues & CUE_PROXY) != 0 && (base.cues & CUE_ADMIN) != 0) {
                return (CONTEXT_PROXY_RISK, true);
            }
        }
        return (NO_NEURAL_CONTEXT, false);
    }

    function _generate(uint8 context, uint8 variant) private view returns (NeuralOutput memory output) {
        bytes memory model = _payload(modelBlob, MODEL_BYTES, false);
        bytes memory lexicon = _payload(lexiconBlob, LEXICON_BYTES, true);
        bytes memory response = new bytes(MAX_RESPONSE_BYTES);
        uint256 responseLength;
        uint8 previous = TOKEN_BOS;
        uint256 contextKey = uint256(context) * uint256(VARIANTS) + uint256(variant);
        bytes32 trace =
            keccak256(abi.encode(MODEL_SHA256, LEXICON_SHA256, modelCodeHash, lexiconCodeHash, contextKey, variant));

        output.context = context;
        output.variant = variant;
        for (uint256 position; position < MAX_GENERATED_TOKENS; ++position) {
            int256[32] memory activation;
            for (uint256 hiddenIndex; hiddenIndex < HIDDEN_UNITS; ++hiddenIndex) {
                int256 value = _i8(model, CONTEXT_EMBEDDINGS_OFFSET + contextKey * HIDDEN_UNITS + hiddenIndex)
                    + _i8(model, TOKEN_EMBEDDINGS_OFFSET + uint256(previous) * HIDDEN_UNITS + hiddenIndex)
                    + _i8(model, POSITION_EMBEDDINGS_OFFSET + position * HIDDEN_UNITS + hiddenIndex);
                activation[hiddenIndex] = _clampActivation(value);
            }
            uint8 selected = TOKEN_EOS;
            int256 selectedScore = type(int256).min;
            for (uint256 candidate = TOKEN_EOS; candidate < VOCABULARY_TOKENS; ++candidate) {
                int256 candidateScore = int256(_i16(model, OUTPUT_BIAS_OFFSET + candidate * 2));
                uint256 row = OUTPUT_WEIGHTS_OFFSET + candidate * HIDDEN_UNITS;
                for (uint256 hiddenIndex; hiddenIndex < HIDDEN_UNITS; ++hiddenIndex) {
                    candidateScore += int256(_i8(model, row + hiddenIndex)) * int256(activation[hiddenIndex]);
                }
                if (candidateScore > selectedScore) {
                    selected = uint8(candidate);
                    selectedScore = candidateScore;
                }
            }

            output.tokenIds[position] = selected;
            output.tokenScores[position] = int32(selectedScore);
            output.stepCount = uint8(position + 1);
            trace = keccak256(abi.encodePacked(trace, position, previous, selected, selectedScore));
            if (selected == TOKEN_EOS) break;

            responseLength = _appendToken(response, responseLength, lexicon, selected);
            output.tokenCount += 1;
            previous = selected;
        }

        assembly ("memory-safe") {
            mstore(response, responseLength)
        }
        output.response = string(response);
        output.traceHash = trace;
    }

    function _appendToken(bytes memory output, uint256 outputLength, bytes memory lexicon, uint8 token)
        private
        pure
        returns (uint256 nextLength)
    {
        uint256 start = _u16(lexicon, LEXICON_OFFSETS_OFFSET + uint256(token) * 2);
        uint256 end = _u16(lexicon, LEXICON_OFFSETS_OFFSET + (uint256(token) + 1) * 2);
        uint256 length = end - start;
        nextLength = outputLength + length;
        if (nextLength > output.length) revert InvalidLexicon();
        uint256 source = LEXICON_DATA_OFFSET + start;
        for (uint256 index; index < length; ++index) {
            output[outputLength + index] = lexicon[source + index];
        }
    }

    function _payload(address blob, uint256 expectedBytes, bool lexicon) private view returns (bytes memory payload) {
        if (blob.code.length != expectedBytes + 1) {
            if (lexicon) revert InvalidLexicon();
            revert InvalidModel();
        }
        payload = new bytes(expectedBytes);
        assembly ("memory-safe") {
            extcodecopy(blob, add(payload, 0x20), 1, expectedBytes)
        }
    }

    function _bytes4(bytes memory data, uint256 offset) private pure returns (bytes4 result) {
        assembly ("memory-safe") {
            result := mload(add(add(data, 0x20), offset))
        }
    }

    function _u16(bytes memory data, uint256 offset) private pure returns (uint16) {
        return uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
    }

    function _i8(bytes memory data, uint256 offset) private pure returns (int256) {
        uint8 raw = uint8(data[offset]);
        if (raw < 128) return int256(uint256(raw));
        return int256(uint256(raw)) - 256;
    }

    function _i16(bytes memory data, uint256 offset) private pure returns (int256) {
        uint16 raw = _u16(data, offset);
        if (raw < 32_768) return int256(uint256(raw));
        return int256(uint256(raw)) - 65_536;
    }

    function _clampActivation(int256 value) private pure returns (int256) {
        if (value > int256(uint256(ACTIVATION_LIMIT))) return int256(uint256(ACTIVATION_LIMIT));
        if (value < -int256(uint256(ACTIVATION_LIMIT))) return -int256(uint256(ACTIVATION_LIMIT));
        return value;
    }
}
