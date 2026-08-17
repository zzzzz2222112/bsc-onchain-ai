// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {TinyAIModelCard} from "./TinyAIModelCard.sol";

/// @notice TinyAI v3: deterministic sparse semantic inference, memory, and payment inside the EVM.
contract TinyAIChat is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant VERSION = 3;
    uint8 public constant INTENT_COUNT = 27;
    uint8 public constant SENTIMENT_COUNT = 3;
    uint8 public constant FOLLOWUP_INTENT = 25;
    uint8 public constant UNKNOWN_INTENT = 26;
    uint8 public constant NO_SECONDARY_INTENT = type(uint8).max;
    uint8 public constant VARIANTS = 4;
    uint256 public constant MAX_PROMPT_BYTES = 280;
    address public constant BURN_SINK = 0x000000000000000000000000000000000000dEaD;

    uint256 private constant MODEL_BYTES = 514_254;
    uint256 private constant MODEL_CHUNK_BYTES = 24_000;
    uint256 private constant MODEL_HEADER_BYTES = 76;
    uint256 private constant MODEL_ENTRY_BYTES = 38;
    uint256 private constant ACTIVE_FEATURES = 13_531;
    uint256 private constant INTENT_BIAS_OFFSET = 16;
    uint256 private constant SENTIMENT_BIAS_OFFSET = 70;
    uint64 private constant FNV_OFFSET = 0xCBF29CE484222325;
    uint64 private constant FNV_PRIME = 0x00000100000001B3;

    TinyAIModelCard public immutable modelCard;
    address private immutable _modelBlob0;
    address private immutable _modelBlob1;
    address private immutable _modelBlob2;
    address private immutable _modelBlob3;
    address private immutable _modelBlob4;
    address private immutable _modelBlob5;
    address private immutable _modelBlob6;
    address private immutable _modelBlob7;
    address private immutable _modelBlob8;
    address private immutable _modelBlob9;
    address private immutable _modelBlob10;
    address private immutable _modelBlob11;
    address private immutable _modelBlob12;
    address private immutable _modelBlob13;
    address private immutable _modelBlob14;
    address private immutable _modelBlob15;
    address private immutable _modelBlob16;
    address private immutable _modelBlob17;
    address private immutable _modelBlob18;
    address private immutable _modelBlob19;
    address private immutable _modelBlob20;
    address private immutable _modelBlob21;
    address public immutable zhLexiconBlob;
    address public immutable enLexiconBlob;
    IERC20 public immutable paymentToken;
    address public immutable treasury;
    uint256 public immutable feePerChat;
    uint16 public immutable burnBps;

    uint64 public totalChats;

    struct Memory {
        uint32 turns;
        uint8 lastIntent;
        int8 mood;
        uint16 confidence;
        bytes32 rollingContext;
    }

    struct InferenceResult {
        string response;
        uint8 intent;
        uint8 secondaryIntent;
        uint8 sentiment;
        int8 nextMood;
        uint16 confidence;
        uint8 variant;
        bytes32 nextContext;
        bool chinese;
        bool followedContext;
    }

    struct ScoreState {
        int256[27] intents;
        int256[3] sentiments;
        uint16 recognized;
        bool chinese;
    }

    struct Decision {
        uint8 intent;
        uint8 secondaryIntent;
        uint8 sentiment;
        int8 nextMood;
        uint16 confidence;
        bool followedContext;
    }

    mapping(address user => Memory memoryState) private _memories;

    event Chat(
        address indexed user,
        uint32 indexed turn,
        uint8 indexed intent,
        uint8 secondaryIntent,
        uint8 sentiment,
        int8 mood,
        uint16 confidence,
        uint8 variant,
        uint256 feePaid,
        string prompt,
        string response,
        bytes32 contextHash,
        bool followedContext
    );

    error EmptyPrompt();
    error PromptTooLong(uint256 length);
    error InvalidFeeConfiguration();
    error PermitUnavailable();
    error ModelIntegrityFailure();
    error CorruptLexicon();

    constructor(
        TinyAIModelCard modelCard_,
        IERC20 paymentToken_,
        address treasury_,
        uint256 feePerChat_,
        uint16 burnBps_
    ) {
        if (address(modelCard_) == address(0) || !modelCard_.integrityOk()) {
            revert ModelIntegrityFailure();
        }
        if (burnBps_ > 10_000 || (feePerChat_ > 0 && (address(paymentToken_) == address(0) || treasury_ == address(0))))
        {
            revert InvalidFeeConfiguration();
        }
        modelCard = modelCard_;
        _modelBlob0 = modelCard_.weightsBlobs(0);
        _modelBlob1 = modelCard_.weightsBlobs(1);
        _modelBlob2 = modelCard_.weightsBlobs(2);
        _modelBlob3 = modelCard_.weightsBlobs(3);
        _modelBlob4 = modelCard_.weightsBlobs(4);
        _modelBlob5 = modelCard_.weightsBlobs(5);
        _modelBlob6 = modelCard_.weightsBlobs(6);
        _modelBlob7 = modelCard_.weightsBlobs(7);
        _modelBlob8 = modelCard_.weightsBlobs(8);
        _modelBlob9 = modelCard_.weightsBlobs(9);
        _modelBlob10 = modelCard_.weightsBlobs(10);
        _modelBlob11 = modelCard_.weightsBlobs(11);
        _modelBlob12 = modelCard_.weightsBlobs(12);
        _modelBlob13 = modelCard_.weightsBlobs(13);
        _modelBlob14 = modelCard_.weightsBlobs(14);
        _modelBlob15 = modelCard_.weightsBlobs(15);
        _modelBlob16 = modelCard_.weightsBlobs(16);
        _modelBlob17 = modelCard_.weightsBlobs(17);
        _modelBlob18 = modelCard_.weightsBlobs(18);
        _modelBlob19 = modelCard_.weightsBlobs(19);
        _modelBlob20 = modelCard_.weightsBlobs(20);
        _modelBlob21 = modelCard_.weightsBlobs(21);
        zhLexiconBlob = modelCard_.zhLexiconBlob();
        enLexiconBlob = modelCard_.enLexiconBlob();
        paymentToken = paymentToken_;
        treasury = treasury_;
        feePerChat = feePerChat_;
        burnBps = burnBps_;
    }

    function memoryOf(address user) external view returns (Memory memory) {
        return _memories[user];
    }

    function preview(address user, string calldata prompt) external view returns (InferenceResult memory) {
        _validatePrompt(bytes(prompt));
        return _infer(user, bytes(prompt), _memories[user]);
    }

    function chat(string calldata prompt) external nonReentrant returns (InferenceResult memory result) {
        return _chat(msg.sender, prompt);
    }

    function chatWithPermit(string calldata prompt, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
        returns (InferenceResult memory result)
    {
        if (address(paymentToken) == address(0) || feePerChat == 0) revert PermitUnavailable();
        IERC20Permit(address(paymentToken)).permit(msg.sender, address(this), feePerChat, deadline, v, r, s);
        return _chat(msg.sender, prompt);
    }

    function _chat(address user, string calldata prompt) private returns (InferenceResult memory result) {
        bytes memory promptBytes = bytes(prompt);
        _validatePrompt(promptBytes);
        _collectFee(user);
        Memory memory prior = _memories[user];
        result = _infer(user, promptBytes, prior);
        uint32 nextTurn = prior.turns + 1;
        _memories[user] = Memory({
            turns: nextTurn,
            lastIntent: result.intent,
            mood: result.nextMood,
            confidence: result.confidence,
            rollingContext: result.nextContext
        });
        totalChats += 1;
        emit Chat(
            user,
            nextTurn,
            result.intent,
            result.secondaryIntent,
            result.sentiment,
            result.nextMood,
            result.confidence,
            result.variant,
            feePerChat,
            prompt,
            result.response,
            result.nextContext,
            result.followedContext
        );
    }

    function _collectFee(address payer) private {
        uint256 fee = feePerChat;
        if (fee == 0) return;
        uint256 burnAmount = fee * burnBps / 10_000;
        uint256 treasuryAmount = fee - burnAmount;
        if (burnAmount != 0) paymentToken.safeTransferFrom(payer, BURN_SINK, burnAmount);
        if (treasuryAmount != 0) paymentToken.safeTransferFrom(payer, treasury, treasuryAmount);
    }

    function _infer(address user, bytes memory prompt, Memory memory prior)
        private
        view
        returns (InferenceResult memory result)
    {
        bytes memory model = _copyModel();
        ScoreState memory state = _scorePrompt(model, prompt);
        if (prior.turns != 0 && prior.lastIntent < INTENT_COUNT) state.intents[prior.lastIntent] += 12;
        Decision memory decision = _makeDecision(state, prior, prompt);
        uint8 variant = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(
                        user,
                        prior.rollingContext,
                        keccak256(prompt),
                        prior.turns,
                        decision.intent,
                        decision.secondaryIntent,
                        decision.nextMood
                    )
                )
            ) % VARIANTS
        );
        string memory response = _reply(state.chinese ? zhLexiconBlob : enLexiconBlob, decision.intent, variant);
        if (decision.secondaryIntent != NO_SECONDARY_INTENT) {
            string memory secondary = _reply(
                state.chinese ? zhLexiconBlob : enLexiconBlob, decision.secondaryIntent, uint8((variant + 1) % VARIANTS)
            );
            response = string.concat(response, state.chinese ? unicode"\n\n另外：" : "\n\nAlso: ", secondary);
        }
        bytes32 nextContext = keccak256(
            abi.encodePacked(
                prior.rollingContext,
                keccak256(prompt),
                keccak256(bytes(response)),
                decision.intent,
                decision.secondaryIntent,
                decision.sentiment,
                decision.nextMood,
                decision.followedContext
            )
        );
        return InferenceResult({
            response: response,
            intent: decision.intent,
            secondaryIntent: decision.secondaryIntent,
            sentiment: decision.sentiment,
            nextMood: decision.nextMood,
            confidence: decision.confidence,
            variant: variant,
            nextContext: nextContext,
            chinese: state.chinese,
            followedContext: decision.followedContext
        });
    }

    function _makeDecision(ScoreState memory state, Memory memory prior, bytes memory prompt)
        private
        pure
        returns (Decision memory decision)
    {
        int256 topScore;
        int256 secondScore;
        (decision.intent, decision.secondaryIntent, topScore, secondScore) = _rankIntents(state);
        decision.sentiment = _rankSentiment(state);
        if (state.recognized == 0) {
            decision.secondaryIntent = decision.intent;
            secondScore = topScore;
            decision.intent = UNKNOWN_INTENT;
            topScore = state.intents[UNKNOWN_INTENT];
        }
        if (decision.intent == FOLLOWUP_INTENT) {
            decision.followedContext = prior.turns != 0 && prior.lastIntent < FOLLOWUP_INTENT;
            decision.intent = decision.followedContext ? prior.lastIntent : UNKNOWN_INTENT;
            decision.secondaryIntent = NO_SECONDARY_INTENT;
        } else if (
            !_hasMultiCue(prompt) || decision.intent == UNKNOWN_INTENT || decision.secondaryIntent == FOLLOWUP_INTENT
                || decision.secondaryIntent == UNKNOWN_INTENT || decision.secondaryIntent == decision.intent
        ) {
            decision.secondaryIntent = NO_SECONDARY_INTENT;
        }
        decision.nextMood = prior.mood;
        if (decision.sentiment == 0 && decision.nextMood > -5) decision.nextMood -= 1;
        if (decision.sentiment == 2 && decision.nextMood < 5) decision.nextMood += 1;
        // The branch proves the signed difference is non-negative.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 margin = topScore > secondScore ? uint256(topScore - secondScore) : 0;
        uint256 magnitude = _absolute(topScore) + _absolute(secondScore) + 1;
        decision.confidence = uint16(_min(9_500, 3_000 + margin * 6_500 / magnitude));
    }

    function _scorePrompt(bytes memory model, bytes memory input) private pure returns (ScoreState memory state) {
        for (uint8 intent; intent < INTENT_COUNT; ++intent) {
            state.intents[intent] = _readI16(model, INTENT_BIAS_OFFSET + uint256(intent) * 2);
        }
        for (uint8 sentiment; sentiment < SENTIMENT_COUNT; ++sentiment) {
            state.sentiments[sentiment] = _readI16(model, SENTIMENT_BIAS_OFFSET + uint256(sentiment) * 2);
        }

        uint256 cursor = 0;
        uint16 codepoints = 0;
        uint256 wordStart = type(uint256).max;
        uint256[4] memory cjkStarts = [uint256(0), uint256(0), uint256(0), uint256(0)];
        uint8 cjkRun = 0;
        while (cursor < input.length && codepoints < 96) {
            uint256 cpStart = cursor;
            (uint32 cp, uint256 width) = _decodeUtf8(input, cursor);
            cursor += width;
            codepoints += 1;

            bool wordPart =
                (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || cp == 45 || cp == 39;
            if (wordPart) {
                if (wordStart == type(uint256).max) wordStart = cpStart;
            } else if (wordStart != type(uint256).max) {
                _applyWord(model, input, wordStart, cpStart, state);
                wordStart = type(uint256).max;
            }

            bool isCjk = cp >= 0x3400 && cp <= 0x9FFF;
            if (isCjk) {
                state.chinese = true;
                cjkStarts[3] = cjkStarts[2];
                cjkStarts[2] = cjkStarts[1];
                cjkStarts[1] = cjkStarts[0];
                cjkStarts[0] = cpStart;
                if (cjkRun < 4) cjkRun += 1;
                for (uint8 size = 1; size <= cjkRun; ++size) {
                    _applyFeature(model, _hashCjk(input, cjkStarts[size - 1], cursor, size), state);
                }
            } else {
                cjkRun = 0;
            }
        }
        if (wordStart != type(uint256).max) _applyWord(model, input, wordStart, cursor, state);
    }

    function _applyWord(bytes memory model, bytes memory input, uint256 start, uint256 end, ScoreState memory state)
        private
        pure
    {
        if (end <= start) return;
        _applyFeature(model, _hashWord(input, start, end, 0), state);
        uint256 length = end - start;
        if (length >= 7 && _endsWith(input, start, end, "ies")) {
            _applyFeature(model, _hashWord(input, start, end - 3, 121), state);
        } else if (length >= 7 && _endsWith(input, start, end, "ing")) {
            _applyFeature(model, _hashWord(input, start, end - 3, 0), state);
        } else if (length >= 6 && _endsWith(input, start, end, "ed")) {
            _applyFeature(model, _hashWord(input, start, end - 2, 0), state);
        } else if (length >= 6 && _endsWith(input, start, end, "es")) {
            _applyFeature(model, _hashWord(input, start, end - 2, 0), state);
        } else if (length >= 5 && _lower(uint8(input[end - 1])) == 115) {
            _applyFeature(model, _hashWord(input, start, end - 1, 0), state);
        }
    }

    function _applyFeature(bytes memory model, uint64 featureId, ScoreState memory state) private pure {
        uint256 low = 0;
        uint256 high = ACTIVE_FEATURES;
        while (low < high) {
            uint256 middle = (low + high) >> 1;
            uint256 offset = MODEL_HEADER_BYTES + middle * MODEL_ENTRY_BYTES;
            uint64 candidate = _readU64(model, offset);
            if (candidate < featureId) low = middle + 1;
            else high = middle;
        }
        if (low >= ACTIVE_FEATURES) return;
        uint256 entry = MODEL_HEADER_BYTES + low * MODEL_ENTRY_BYTES;
        if (_readU64(model, entry) != featureId) return;
        for (uint8 intent; intent < INTENT_COUNT; ++intent) {
            state.intents[intent] += _readI8(model, entry + 8 + intent);
        }
        for (uint8 sentiment; sentiment < SENTIMENT_COUNT; ++sentiment) {
            state.sentiments[sentiment] += _readI8(model, entry + 8 + INTENT_COUNT + sentiment);
        }
        state.recognized += 1;
    }

    function _rankIntents(ScoreState memory state)
        private
        pure
        returns (uint8 topIntent, uint8 secondIntent, int256 topScore, int256 secondScore)
    {
        topScore = type(int256).min;
        secondScore = type(int256).min;
        for (uint8 intent; intent < INTENT_COUNT; ++intent) {
            int256 current = state.intents[intent];
            if (current > topScore) {
                secondScore = topScore;
                secondIntent = topIntent;
                topScore = current;
                topIntent = intent;
            } else if (current > secondScore) {
                secondScore = current;
                secondIntent = intent;
            }
        }
    }

    function _rankSentiment(ScoreState memory state) private pure returns (uint8 result) {
        if (state.sentiments[1] > state.sentiments[0]) result = 1;
        if (state.sentiments[2] > state.sentiments[result]) result = 2;
    }

    function _hashWord(bytes memory input, uint256 start, uint256 end, uint8 appended)
        private
        pure
        returns (uint64 hash)
    {
        hash = _fnv(_fnv(FNV_OFFSET, 119), 58); // "w:"
        for (uint256 index = start; index < end; ++index) {
            hash = _fnv(hash, _lower(uint8(input[index])));
        }
        if (appended != 0) hash = _fnv(hash, appended);
    }

    function _hashCjk(bytes memory input, uint256 start, uint256 end, uint8 size) private pure returns (uint64 hash) {
        hash = _fnv(_fnv(_fnv(FNV_OFFSET, 122), 48 + size), 58); // "zN:"
        for (uint256 index = start; index < end; ++index) {
            hash = _fnv(hash, uint8(input[index]));
        }
    }

    function _fnv(uint64 hash, uint8 value) private pure returns (uint64) {
        unchecked {
            return (hash ^ uint64(value)) * FNV_PRIME;
        }
    }

    function _lower(uint8 value) private pure returns (uint8) {
        return value >= 65 && value <= 90 ? value + 32 : value;
    }

    function _endsWith(bytes memory input, uint256 start, uint256 end, string memory suffix)
        private
        pure
        returns (bool)
    {
        bytes memory needle = bytes(suffix);
        if (end - start < needle.length) return false;
        uint256 offset = end - needle.length;
        for (uint256 index; index < needle.length; ++index) {
            if (_lower(uint8(input[offset + index])) != uint8(needle[index])) return false;
        }
        return true;
    }

    function _hasMultiCue(bytes memory prompt) private pure returns (bool) {
        return _contains(prompt, bytes(" and ")) || _contains(prompt, bytes(" plus "))
            || _contains(prompt, bytes(" while ")) || _contains(prompt, bytes(";"))
            || _contains(prompt, bytes(unicode"同时")) || _contains(prompt, bytes(unicode"另外"))
            || _contains(prompt, bytes(unicode"以及")) || _contains(prompt, bytes(unicode"并且"))
            || _contains(prompt, bytes(unicode"顺便")) || _contains(prompt, bytes(unicode"还要"))
            || _contains(prompt, bytes(unicode"再说"));
    }

    function _contains(bytes memory haystack, bytes memory needle) private pure returns (bool) {
        if (needle.length == 0 || needle.length > haystack.length) return false;
        for (uint256 start; start + needle.length <= haystack.length; ++start) {
            bool matched = true;
            for (uint256 index; index < needle.length; ++index) {
                uint8 left = uint8(haystack[start + index]);
                uint8 right = uint8(needle[index]);
                if (_lower(left) != _lower(right)) {
                    matched = false;
                    break;
                }
            }
            if (matched) return true;
        }
        return false;
    }

    function _decodeUtf8(bytes memory data, uint256 offset) private pure returns (uint32 cp, uint256 width) {
        uint8 first = uint8(data[offset]);
        if (first < 0x80) return (first, 1);
        if (first >= 0xC2 && first <= 0xDF && offset + 1 < data.length) {
            uint8 b1 = uint8(data[offset + 1]);
            if ((b1 & 0xC0) == 0x80) return ((uint32(first & 0x1F) << 6) | uint32(b1 & 0x3F), 2);
        }
        if (first >= 0xE0 && first <= 0xEF && offset + 2 < data.length) {
            uint8 b1 = uint8(data[offset + 1]);
            uint8 b2 = uint8(data[offset + 2]);
            bool valid = (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80;
            valid = valid && !(first == 0xE0 && b1 < 0xA0) && !(first == 0xED && b1 >= 0xA0);
            if (valid) return ((uint32(first & 0x0F) << 12) | (uint32(b1 & 0x3F) << 6) | uint32(b2 & 0x3F), 3);
        }
        if (first >= 0xF0 && first <= 0xF4 && offset + 3 < data.length) {
            uint8 b1 = uint8(data[offset + 1]);
            uint8 b2 = uint8(data[offset + 2]);
            uint8 b3 = uint8(data[offset + 3]);
            bool valid = (b1 & 0xC0) == 0x80 && (b2 & 0xC0) == 0x80 && (b3 & 0xC0) == 0x80;
            valid = valid && !(first == 0xF0 && b1 < 0x90) && !(first == 0xF4 && b1 >= 0x90);
            if (valid) {
                return (
                    (uint32(first & 0x07) << 18) | (uint32(b1 & 0x3F) << 12) | (uint32(b2 & 0x3F) << 6)
                        | uint32(b3 & 0x3F),
                    4
                );
            }
        }
        return (0xFFFD, 1);
    }

    function _reply(address blob, uint8 intent, uint8 variant) private view returns (string memory) {
        uint256 entry = uint256(intent) * VARIANTS + variant;
        bytes32 indexWord = _codeWord(blob, 1 + 9 + entry * 5);
        uint256 offset =
            (uint256(uint8(indexWord[0])) << 16) | (uint256(uint8(indexWord[1])) << 8) | uint256(uint8(indexWord[2]));
        uint256 length = (uint256(uint8(indexWord[3])) << 8) | uint256(uint8(indexWord[4]));
        if (length == 0 || offset + length > blob.code.length - 1) revert CorruptLexicon();
        bytes memory output = new bytes(length);
        assembly ("memory-safe") {
            extcodecopy(blob, add(output, 0x20), add(offset, 1), length)
        }
        return string(output);
    }

    function _copyModel() private view returns (bytes memory output) {
        output = new bytes(MODEL_BYTES);
        _copyModelChunk(output, _modelBlob0, 0, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob1, MODEL_CHUNK_BYTES, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob2, MODEL_CHUNK_BYTES * 2, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob3, MODEL_CHUNK_BYTES * 3, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob4, MODEL_CHUNK_BYTES * 4, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob5, MODEL_CHUNK_BYTES * 5, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob6, MODEL_CHUNK_BYTES * 6, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob7, MODEL_CHUNK_BYTES * 7, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob8, MODEL_CHUNK_BYTES * 8, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob9, MODEL_CHUNK_BYTES * 9, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob10, MODEL_CHUNK_BYTES * 10, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob11, MODEL_CHUNK_BYTES * 11, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob12, MODEL_CHUNK_BYTES * 12, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob13, MODEL_CHUNK_BYTES * 13, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob14, MODEL_CHUNK_BYTES * 14, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob15, MODEL_CHUNK_BYTES * 15, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob16, MODEL_CHUNK_BYTES * 16, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob17, MODEL_CHUNK_BYTES * 17, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob18, MODEL_CHUNK_BYTES * 18, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob19, MODEL_CHUNK_BYTES * 19, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob20, MODEL_CHUNK_BYTES * 20, MODEL_CHUNK_BYTES);
        _copyModelChunk(output, _modelBlob21, MODEL_CHUNK_BYTES * 21, MODEL_BYTES - MODEL_CHUNK_BYTES * 21);
    }

    function _copyModelChunk(bytes memory output, address blob, uint256 destinationOffset, uint256 payloadLength)
        private
        view
    {
        if (blob.code.length != payloadLength + 1) revert ModelIntegrityFailure();
        assembly ("memory-safe") {
            extcodecopy(blob, add(add(output, 0x20), destinationOffset), 1, payloadLength)
        }
    }

    function _codeWord(address blob, uint256 offset) private view returns (bytes32 word) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            extcodecopy(blob, ptr, offset, 0x20)
            word := mload(ptr)
        }
    }

    function _readU64(bytes memory data, uint256 offset) private pure returns (uint64 value) {
        assembly ("memory-safe") {
            value := shr(192, mload(add(add(data, 0x20), offset)))
        }
    }

    function _readI8(bytes memory data, uint256 offset) private pure returns (int256) {
        uint8 raw = _byte(data, offset);
        return raw < 128 ? int256(uint256(raw)) : int256(uint256(raw)) - 256;
    }

    function _readI16(bytes memory data, uint256 offset) private pure returns (int256) {
        uint16 raw = (uint16(_byte(data, offset)) << 8) | uint16(_byte(data, offset + 1));
        return raw < 32_768 ? int256(uint256(raw)) : int256(uint256(raw)) - 65_536;
    }

    function _byte(bytes memory data, uint256 offset) private pure returns (uint8 value) {
        assembly ("memory-safe") {
            value := byte(0, mload(add(add(data, 0x20), offset)))
        }
    }

    function _validatePrompt(bytes memory prompt) private pure {
        if (prompt.length == 0) revert EmptyPrompt();
        if (prompt.length > MAX_PROMPT_BYTES) revert PromptTooLong(prompt.length);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _absolute(int256 value) private pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (value >= 0) return uint256(value);
        return uint256(-(value + 1)) + 1;
    }
}
