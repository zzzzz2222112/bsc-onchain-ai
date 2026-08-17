// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Immutable identity and integrity record for one TinyAI model version.
contract TinyAIModelCard {
    uint8 public constant VERSION = 3;
    uint8 public constant INTENT_COUNT = 27;
    uint8 public constant SENTIMENT_COUNT = 3;
    uint8 public constant VARIANTS_PER_INTENT = 4;
    uint8 public constant MODEL_CHUNK_COUNT = 22;
    uint16 public constant MODEL_ENTRY_BYTES = 38;
    uint16 public constant MODEL_HEADER_BYTES = 76;
    uint32 public constant ACTIVE_FEATURES = 13_531;
    uint256 public constant MODEL_BYTES = 514_254;
    uint256 public constant MODEL_CHUNK_BYTES = 24_000;
    uint64 public constant RELEASED_AT = 1_786_838_400; // 2026-08-16T00:00:00Z

    address[22] public weightsBlobs;
    bytes32[22] public weightsCodeHashes;
    address public immutable zhLexiconBlob;
    address public immutable enLexiconBlob;
    bytes32 public immutable zhLexiconCodeHash;
    bytes32 public immutable enLexiconCodeHash;
    bytes32 public immutable corpusSha256;

    string public constant ARCHITECTURE =
        "bounded semantic tokens -> sorted uint64 dictionary -> int8 intent/sentiment heads -> immutable replies";
    string public constant TRUTH_BOUNDARY =
        "training off-chain; tokenisation, lookup, integer inference, context, selection, and output on-chain";
    string public constant CAPACITY_BOUNDARY =
        "bounded semantic classifier with fixed replies, not a generative LLM or live-data oracle";

    error InvalidBlob(address blob);
    error InvalidModelHeader();
    error InvalidLexiconHeader(address blob, uint8 expectedLanguage);

    constructor(address[22] memory modelBlobs_, address zhLexicon_, address enLexicon_, bytes32 corpusSha256_) {
        for (uint256 index; index < MODEL_CHUNK_COUNT; ++index) {
            address blob = modelBlobs_[index];
            if (blob.code.length != _chunkPayloadLength(index) + 1 || uint8(_codeWord(blob, 0)[0]) != 0) {
                revert InvalidBlob(blob);
            }
            weightsBlobs[index] = blob;
            weightsCodeHashes[index] = blob.codehash;
        }
        if (!_validModelHeader(modelBlobs_[0])) revert InvalidModelHeader();
        if (!_validLexicon(zhLexicon_, 0)) revert InvalidLexiconHeader(zhLexicon_, 0);
        if (!_validLexicon(enLexicon_, 1)) revert InvalidLexiconHeader(enLexicon_, 1);

        zhLexiconBlob = zhLexicon_;
        enLexiconBlob = enLexicon_;
        zhLexiconCodeHash = zhLexicon_.codehash;
        enLexiconCodeHash = enLexicon_.codehash;
        corpusSha256 = corpusSha256_;
    }

    /// @notice Fixed release timestamp for reproducible runtime bytecode across deployments.
    function publishedAt() external pure returns (uint64) {
        return RELEASED_AT;
    }

    function integrityOk() external view returns (bool) {
        for (uint256 index; index < MODEL_CHUNK_COUNT; ++index) {
            if (weightsBlobs[index].codehash != weightsCodeHashes[index]) return false;
        }
        return zhLexiconBlob.codehash == zhLexiconCodeHash && enLexiconBlob.codehash == enLexiconCodeHash;
    }

    function weightChunkPayloadLength(uint256 index) external pure returns (uint256) {
        if (index >= MODEL_CHUNK_COUNT) return 0;
        return _chunkPayloadLength(index);
    }

    function _validModelHeader(address blob) private view returns (bool) {
        bytes32 word = _codeWord(blob, 1);
        uint16 entryBytes = uint16(uint8(word[8])) << 8 | uint16(uint8(word[9]));
        uint32 entries = uint32(uint8(word[10])) << 24 | uint32(uint8(word[11])) << 16 | uint32(uint8(word[12])) << 8
            | uint32(uint8(word[13]));
        uint16 headerBytes = uint16(uint8(word[14])) << 8 | uint16(uint8(word[15]));
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(word) == bytes4("TAS1") && uint8(word[4]) == VERSION && uint8(word[5]) == INTENT_COUNT
            && uint8(word[6]) == SENTIMENT_COUNT && uint8(word[7]) == 96 && entryBytes == MODEL_ENTRY_BYTES
            && entries == ACTIVE_FEATURES && headerBytes == MODEL_HEADER_BYTES;
    }

    function _validLexicon(address blob, uint8 language) private view returns (bool) {
        if (blob.code.length < 1_001 || blob.code.length > 24_576 || uint8(_codeWord(blob, 0)[0]) != 0) return false;
        bytes32 word = _codeWord(blob, 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(word) == bytes4("TAL1") && uint8(word[4]) == VERSION && uint8(word[5]) == INTENT_COUNT
            && uint8(word[6]) == VARIANTS_PER_INTENT && uint8(word[7]) == 1 && uint8(word[8]) == language;
    }

    function _chunkPayloadLength(uint256 index) private pure returns (uint256) {
        uint256 offset = index * MODEL_CHUNK_BYTES;
        uint256 remaining = MODEL_BYTES - offset;
        return remaining > MODEL_CHUNK_BYTES ? MODEL_CHUNK_BYTES : remaining;
    }

    function _codeWord(address blob, uint256 offset) private view returns (bytes32 word) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            extcodecopy(blob, ptr, offset, 0x20)
            word := mload(ptr)
        }
    }
}
