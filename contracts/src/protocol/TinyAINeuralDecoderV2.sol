// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Gas-bounded decoder for the immutable TinyAI v6 int8 neural model.
/// @dev It evaluates the same embeddings and complete 133-token vocabulary head as
///      TinyAIGeneratorV6, but performs the hot matrix loops in checked-equivalent Yul.
contract TinyAINeuralDecoderV2 {
    uint8 public constant VERSION = 2;
    uint8 public constant MODEL_VERSION = 6;
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

    address public immutable modelBlob;
    address public immutable lexiconBlob;
    bytes32 public immutable modelCodeHash;
    bytes32 public immutable lexiconCodeHash;

    error InvalidModel();
    error InvalidLexicon();
    error InvalidNeuralContext(uint8 context);
    error InvalidVariant(uint8 variant);

    constructor(address modelBlob_, address lexiconBlob_) {
        bytes memory model = _payload(modelBlob_, MODEL_BYTES, false);
        if (
            _bytes4(model, 0) != bytes4("TAG6") || uint8(model[4]) != MODEL_VERSION || uint8(model[5]) != CONTEXT_KEYS
                || uint8(model[6]) != VOCABULARY_TOKENS || uint8(model[7]) != HIDDEN_UNITS
                || uint8(model[8]) != MAX_GENERATED_TOKENS || uint8(model[9]) != ACTIVATION_LIMIT
                || sha256(model) != MODEL_SHA256
        ) revert InvalidModel();

        bytes memory lexicon = _payload(lexiconBlob_, LEXICON_BYTES, true);
        if (
            _bytes4(lexicon, 0) != bytes4("TAL6") || uint8(lexicon[4]) != MODEL_VERSION
                || uint8(lexicon[5]) != VOCABULARY_TOKENS || sha256(lexicon) != LEXICON_SHA256
        ) revert InvalidLexicon();

        modelBlob = modelBlob_;
        lexiconBlob = lexiconBlob_;
        modelCodeHash = modelBlob_.codehash;
        lexiconCodeHash = lexiconBlob_.codehash;
    }

    function architecture() external pure returns (string memory) {
        return "TinyAI v6 int8 embeddings and full vocabulary head; exact Yul matrix evaluation; greedy token decode";
    }

    function integrityOk() external view returns (bool) {
        return modelBlob.codehash == modelCodeHash && lexiconBlob.codehash == lexiconCodeHash;
    }

    function generateFromContext(uint8 context, uint8 variant) external view returns (NeuralOutput memory) {
        if (context >= NEURAL_CONTEXTS) revert InvalidNeuralContext(context);
        if (variant >= VARIANTS) revert InvalidVariant(variant);
        return _generate(context, variant);
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
            _fillActivation(model, activation, contextKey, previous, position);
            (uint8 selected, int256 selectedScore) = _selectToken(model, activation);

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

    function _fillActivation(
        bytes memory model,
        int256[32] memory activation,
        uint256 contextKey,
        uint8 previous,
        uint256 position
    ) private pure {
        uint256 contextOffset = CONTEXT_EMBEDDINGS_OFFSET + contextKey * HIDDEN_UNITS;
        uint256 tokenOffset = TOKEN_EMBEDDINGS_OFFSET + uint256(previous) * HIDDEN_UNITS;
        uint256 positionOffset = POSITION_EMBEDDINGS_OFFSET + position * HIDDEN_UNITS;
        assembly ("memory-safe") {
            let data := add(model, 0x20)
            for { let hiddenIndex := 0 } lt(hiddenIndex, 32) { hiddenIndex := add(hiddenIndex, 1) } {
                let contextValue := signextend(0, byte(0, mload(add(add(data, contextOffset), hiddenIndex))))
                let tokenValue := signextend(0, byte(0, mload(add(add(data, tokenOffset), hiddenIndex))))
                let positionValue := signextend(0, byte(0, mload(add(add(data, positionOffset), hiddenIndex))))
                let value := add(add(contextValue, tokenValue), positionValue)
                if sgt(value, 8) { value := 8 }
                if slt(value, sub(0, 8)) { value := sub(0, 8) }
                mstore(add(activation, mul(hiddenIndex, 0x20)), value)
            }
        }
    }

    function _selectToken(bytes memory model, int256[32] memory activation)
        private
        pure
        returns (uint8 selected, int256 selectedScore)
    {
        assembly ("memory-safe") {
            let data := add(model, 0x20)
            let bestToken := 1
            let bestScore := shl(255, 1)
            for { let candidate := 1 } lt(candidate, 133) { candidate := add(candidate, 1) } {
                let biasOffset := add(9808, mul(candidate, 2))
                let score := signextend(1, shr(240, mload(add(data, biasOffset))))
                let row := add(add(data, 5552), mul(candidate, 32))
                for { let hiddenIndex := 0 } lt(hiddenIndex, 32) { hiddenIndex := add(hiddenIndex, 1) } {
                    let weight := signextend(0, byte(0, mload(add(row, hiddenIndex))))
                    score := add(score, mul(weight, mload(add(activation, mul(hiddenIndex, 0x20)))))
                }
                if sgt(score, bestScore) {
                    bestToken := candidate
                    bestScore := score
                }
            }
            selected := bestToken
            selectedScore := bestScore
        }
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

    function _u16(bytes memory data, uint256 offset) private pure returns (uint16 result) {
        assembly ("memory-safe") {
            result := shr(240, mload(add(add(data, 0x20), offset)))
        }
    }
}
