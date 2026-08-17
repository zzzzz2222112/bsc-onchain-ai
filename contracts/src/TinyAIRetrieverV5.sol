// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TinyAIChat} from "./TinyAIChat.sol";
import {TinyAIModelCard} from "./TinyAIModelCard.sol";
import {TinyAIKnowledgeV5} from "./TinyAIKnowledgeV5.sol";

/// @notice TinyAI v5: trained semantic routing followed by bounded fact retrieval and evidence composition.
contract TinyAIRetrieverV5 {
    uint8 public constant VERSION = 5;
    uint256 public constant MAX_PROMPT_BYTES = 280;
    uint8 public constant MAX_FACTS = 3;
    bytes32 public constant KNOWLEDGE_HASH =
        keccak256("TinyAI-v5|v3-trained-router|entity-cues-v1|immutable-facts-v1|evidence-composer|polite-unknown");

    uint8 public constant TOPIC_UNKNOWN = 0;
    uint8 public constant TOPIC_IDENTITY = 1;
    uint8 public constant TOPIC_ONCHAIN = 2;
    uint8 public constant TOPIC_BSC = 3;
    uint8 public constant TOPIC_HUMAN = 4;
    uint8 public constant TOPIC_GAS = 5;
    uint8 public constant TOPIC_WALLET = 6;
    uint8 public constant TOPIC_CONTRACT = 7;
    uint8 public constant TOPIC_TOKEN = 8;
    uint8 public constant TOPIC_DEFI = 9;
    uint8 public constant TOPIC_NFT = 10;
    uint8 public constant TOPIC_TRANSACTION = 11;
    uint8 public constant TOPIC_PRIVACY = 12;
    uint8 public constant TOPIC_GOVERNANCE = 13;
    uint8 public constant TOPIC_PLANNING = 14;
    uint8 public constant TOPIC_MARKET = 15;
    uint8 public constant TOPIC_DIALOGUE = 16;

    uint8 public constant QUERY_UNKNOWN = 0;
    uint8 public constant QUERY_GREETING = 1;
    uint8 public constant QUERY_DEFINE = 2;
    uint8 public constant QUERY_WHY = 3;
    uint8 public constant QUERY_HOW = 4;
    uint8 public constant QUERY_COMPARE = 5;
    uint8 public constant QUERY_RISK = 6;
    uint8 public constant QUERY_FOLLOWUP = 7;

    uint8 private constant FOLLOWUP_INTENT = 25;
    uint8 private constant UNKNOWN_INTENT = 26;

    uint64 public constant CUE_AI = uint64(1) << 0;
    uint64 public constant CUE_SCALE = uint64(1) << 1;
    uint64 public constant CUE_ADMIN = uint64(1) << 2;
    uint64 public constant CUE_MINT = uint64(1) << 3;
    uint64 public constant CUE_PROXY = uint64(1) << 4;
    uint64 public constant CUE_BLACKLIST = uint64(1) << 5;
    uint64 public constant CUE_LIQUIDITY = uint64(1) << 6;
    uint64 public constant CUE_SIGNATURE = uint64(1) << 7;
    uint64 public constant CUE_PRIVATE_KEY = uint64(1) << 8;
    uint64 public constant CUE_LIVE = uint64(1) << 9;
    uint64 public constant CUE_PRICE = uint64(1) << 10;
    uint64 public constant CUE_SECURITY = uint64(1) << 11;
    uint64 public constant CUE_PLANNING = uint64(1) << 12;
    uint64 public constant CUE_CODE = uint64(1) << 13;

    uint8 private constant OP_CLASSIFY = 1;
    uint8 private constant OP_PARSE = 2;
    uint8 private constant OP_RETRIEVE = 3;
    uint8 private constant OP_VERIFY = 4;
    uint8 private constant OP_COMPOSE = 5;

    struct Memory {
        uint32 turns;
        uint8 lastTopic;
        uint8 lastIntent;
        uint16 matchScore;
        bytes32 rollingContext;
    }

    struct RetrievalResult {
        string response;
        string evidence;
        uint8 intent;
        uint8 secondaryIntent;
        uint8 topic;
        uint8 queryType;
        uint16 classifierConfidence;
        uint16 matchScore;
        uint64 cues;
        uint16[3] factIds;
        uint8 factCount;
        bool unknown;
        bool negated;
        bool chinese;
        bool followedContext;
        bytes32 traceHash;
        bytes32 nextContext;
        bytes32[5] trace;
    }

    struct ParseState {
        uint8 explicitTopic;
        uint8 queryType;
        uint64 cues;
        bool negated;
        bool chinese;
        bool explicitFollowup;
    }

    TinyAIChat public immutable classifier;
    TinyAIModelCard public immutable modelCard;
    TinyAIKnowledgeV5 public immutable knowledge;
    bytes32 public immutable classifierCodeHash;
    bytes32 public immutable modelCardCodeHash;
    bytes32 public immutable knowledgeCodeHash;
    uint64 public totalChats;

    mapping(address user => Memory memoryState) private _memories;

    event RetrievedChat(
        address indexed user,
        uint32 indexed turn,
        uint8 indexed topic,
        uint8 intent,
        uint8 queryType,
        uint16 classifierConfidence,
        uint16 matchScore,
        uint64 cues,
        uint16[3] factIds,
        uint8 factCount,
        bool unknown,
        bool negated,
        string prompt,
        string response,
        string evidence,
        bytes32 traceHash,
        bytes32 contextHash
    );

    error EmptyPrompt();
    error PromptTooLong(uint256 length);
    error InvalidClassifier();
    error InvalidKnowledge();

    constructor(TinyAIChat classifier_, TinyAIKnowledgeV5 knowledge_) {
        if (address(classifier_).code.length == 0 || classifier_.VERSION() != 3) revert InvalidClassifier();
        TinyAIModelCard modelCard_ = classifier_.modelCard();
        if (address(modelCard_).code.length == 0 || !modelCard_.integrityOk()) revert InvalidClassifier();
        if (address(knowledge_).code.length == 0 || knowledge_.KNOWLEDGE_HASH() != KNOWLEDGE_HASH) {
            revert InvalidKnowledge();
        }
        classifier = classifier_;
        modelCard = modelCard_;
        knowledge = knowledge_;
        classifierCodeHash = address(classifier_).codehash;
        modelCardCodeHash = address(modelCard_).codehash;
        knowledgeCodeHash = address(knowledge_).codehash;
    }

    function architecture() external pure returns (string memory) {
        return
            "trained v3 sparse classifier -> entity and negation parser -> immutable fact retrieval -> evidence composer";
    }

    function truthBoundary() external pure returns (string memory) {
        return
            "training and fact authoring off-chain; classification, retrieval, composition, output, and memory on-chain";
    }

    function memoryOf(address user) external view returns (Memory memory) {
        return _memories[user];
    }

    function integrityOk() external view returns (bool) {
        return address(classifier).codehash == classifierCodeHash && address(modelCard).codehash == modelCardCodeHash
            && address(knowledge).codehash == knowledgeCodeHash && knowledge.KNOWLEDGE_HASH() == KNOWLEDGE_HASH
            && modelCard.integrityOk();
    }

    function preview(address user, string calldata prompt) external view returns (RetrievalResult memory) {
        _validate(prompt);
        return _reason(user, bytes(prompt), _memories[user]);
    }

    function chat(string calldata prompt) external returns (RetrievalResult memory result) {
        _validate(prompt);
        Memory memory prior = _memories[msg.sender];
        result = _reason(msg.sender, bytes(prompt), prior);
        uint32 turn = prior.turns + 1;
        _memories[msg.sender] = Memory({
            turns: turn,
            lastTopic: result.topic,
            lastIntent: result.intent,
            matchScore: result.matchScore,
            rollingContext: result.nextContext
        });
        totalChats += 1;
        emit RetrievedChat(
            msg.sender,
            turn,
            result.topic,
            result.intent,
            result.queryType,
            result.classifierConfidence,
            result.matchScore,
            result.cues,
            result.factIds,
            result.factCount,
            result.unknown,
            result.negated,
            prompt,
            result.response,
            result.evidence,
            result.traceHash,
            result.nextContext
        );
    }

    function _reason(address user, bytes memory prompt, Memory memory prior)
        private
        view
        returns (RetrievalResult memory result)
    {
        TinyAIChat.InferenceResult memory classified = classifier.preview(address(0), string(prompt));
        ParseState memory parsed = _parse(prompt);
        bool followed = parsed.explicitFollowup && prior.turns != 0 && prior.lastTopic != TOPIC_UNKNOWN;
        uint8 topic = followed ? prior.lastTopic : parsed.explicitTopic;
        if (topic == TOPIC_UNKNOWN) topic = _topicFromIntent(classified.intent, parsed);
        if (classified.intent == FOLLOWUP_INTENT && !followed) topic = TOPIC_UNKNOWN;

        uint16 matchScore = _matchScore(classified.confidence, parsed.explicitTopic != TOPIC_UNKNOWN, topic);
        TinyAIKnowledgeV5.Retrieval memory retrieved = knowledge.answer(
            classified.chinese || parsed.chinese,
            topic,
            followed ? QUERY_FOLLOWUP : parsed.queryType,
            parsed.cues,
            parsed.negated,
            classified.response
        );
        if (retrieved.unknown) {
            topic = TOPIC_UNKNOWN;
            matchScore = 0;
        }

        bytes32[5] memory trace;
        trace[0] = _traceWord(OP_CLASSIFY, classified.intent, classified.secondaryIntent, classified.confidence, 0, 0);
        trace[1] = _traceWord(OP_PARSE, topic, parsed.queryType, matchScore, parsed.cues, 0);
        trace[2] = _traceWord(
            OP_RETRIEVE,
            retrieved.factCount,
            0,
            matchScore,
            uint64(retrieved.factIds[0]) << 32 | uint64(retrieved.factIds[1]) << 16 | retrieved.factIds[2],
            0
        );
        trace[3] = _traceWord(OP_VERIFY, retrieved.unknown ? 1 : 0, parsed.negated ? 1 : 0, matchScore, parsed.cues, 0);
        trace[4] = _traceWord(OP_COMPOSE, topic, retrieved.factCount, matchScore, parsed.cues, 0);

        bytes32 traceHash = keccak256(
            abi.encode(
                KNOWLEDGE_HASH,
                address(classifier),
                classifierCodeHash,
                address(knowledge),
                knowledgeCodeHash,
                user,
                prior.rollingContext,
                keccak256(prompt),
                classified.intent,
                classified.secondaryIntent,
                topic,
                parsed.queryType,
                matchScore,
                parsed.cues,
                retrieved.factIds,
                retrieved.factCount,
                retrieved.unknown,
                parsed.negated,
                trace
            )
        );
        bytes32 nextContext = keccak256(
            abi.encodePacked(
                prior.rollingContext,
                keccak256(prompt),
                keccak256(bytes(retrieved.response)),
                topic,
                classified.intent,
                retrieved.factIds,
                traceHash
            )
        );

        result = RetrievalResult({
            response: retrieved.response,
            evidence: retrieved.evidence,
            intent: classified.intent,
            secondaryIntent: classified.secondaryIntent,
            topic: topic,
            queryType: followed ? QUERY_FOLLOWUP : parsed.queryType,
            classifierConfidence: classified.confidence,
            matchScore: matchScore,
            cues: parsed.cues,
            factIds: retrieved.factIds,
            factCount: retrieved.factCount,
            unknown: retrieved.unknown,
            negated: parsed.negated,
            chinese: classified.chinese || parsed.chinese,
            followedContext: followed,
            traceHash: traceHash,
            nextContext: nextContext,
            trace: trace
        });
    }

    function _parse(bytes memory prompt) private pure returns (ParseState memory parsed) {
        parsed.chinese = _hasCjk(prompt);
        parsed.negated = _containsEither(prompt, unicode"不能", " cannot ")
            || _containsEither(prompt, unicode"不会", " not ") || _containsEither(prompt, unicode"没有", " no ")
            || _containsEither(prompt, unicode"不可以", "can't") || _contains(prompt, bytes("isn't"), true);
        parsed.explicitFollowup = _containsEither(prompt, unicode"继续说", "tell me more")
            || _containsEither(prompt, unicode"然后呢", "go on")
            || _containsEither(prompt, unicode"详细一点", "more detail")
            || _containsEither(prompt, unicode"再解释", "continue");

        if (parsed.explicitFollowup) {
            parsed.queryType = QUERY_FOLLOWUP;
        } else if (_containsEither(prompt, unicode"你好", "hello") || _containsEither(prompt, unicode"嗨", "hi")) {
            parsed.queryType = QUERY_GREETING;
        } else if (
            _containsEither(prompt, unicode"比较", "compare")
                || _containsEither(prompt, unicode"区别", "difference")
        ) {
            parsed.queryType = QUERY_COMPARE;
        } else if (
            _containsEither(prompt, unicode"风险", "risk") || _containsEither(prompt, unicode"安全吗", "safe")
        ) {
            parsed.queryType = QUERY_RISK;
        } else if (_containsEither(prompt, unicode"为什么", "why")) {
            parsed.queryType = QUERY_WHY;
        } else if (_containsEither(prompt, unicode"怎么", "how") || _contains(prompt, bytes(unicode"如何"), false))
        {
            parsed.queryType = QUERY_HOW;
        } else if (
            _containsEither(prompt, unicode"什么是", "what is")
                || _containsEither(prompt, unicode"是什么", "define")
                || _containsEither(prompt, unicode"介绍", "explain")
                || _containsEither(prompt, unicode"知道什么", "do you know")
        ) {
            parsed.queryType = QUERY_DEFINE;
        }

        if (
            _containsEither(prompt, unicode"人工智能", "artificial intelligence")
                || _containsEither(prompt, " ai ", unicode"模型") || _contains(prompt, bytes("AI"), false)
        ) {
            parsed.cues |= CUE_AI;
        }
        if (
            _containsEither(prompt, unicode"十倍", "10x") || _containsEither(prompt, unicode"提高", "increase")
                || _containsEither(prompt, unicode"提升", "improve")
        ) parsed.cues |= CUE_SCALE;
        if (
            _containsEither(prompt, unicode"管理员", "admin") || _containsEither(prompt, "owner", unicode"所有者")
        ) {
            parsed.cues |= CUE_ADMIN;
        }
        if (_containsEither(prompt, unicode"增发", "mint")) parsed.cues |= CUE_MINT;
        if (_containsEither(prompt, unicode"代理", "proxy") || _containsEither(prompt, unicode"升级", "upgrade")) {
            parsed.cues |= CUE_PROXY;
        }
        if (_containsEither(prompt, unicode"黑名单", "blacklist")) parsed.cues |= CUE_BLACKLIST;
        if (_containsEither(prompt, unicode"流动性", "liquidity") || _containsEither(prompt, " lp", unicode"池子"))
        {
            parsed.cues |= CUE_LIQUIDITY;
        }
        if (
            _containsEither(prompt, unicode"签名", "signature") || _containsEither(prompt, unicode"授权", "approve")
        ) parsed.cues |= CUE_SIGNATURE;
        if (
            _containsEither(prompt, unicode"私钥", "private key")
                || _containsEither(prompt, unicode"助记词", "seed phrase")
        ) parsed.cues |= CUE_PRIVATE_KEY;
        if (_containsEither(prompt, unicode"实时", "live") || _containsEither(prompt, unicode"现在", "current")) {
            parsed.cues |= CUE_LIVE;
        }
        if (_containsEither(prompt, unicode"价格", "price") || _containsEither(prompt, unicode"市值", "market cap"))
        {
            parsed.cues |= CUE_PRICE;
        }
        if (
            _containsEither(prompt, unicode"安全", "security") || _containsEither(prompt, unicode"后门", "backdoor")
                || _containsEither(prompt, unicode"风险", "risk")
        ) parsed.cues |= CUE_SECURITY;
        if (
            _containsEither(prompt, unicode"计划", "plan") || _containsEither(prompt, unicode"项目", "project")
                || _containsEither(prompt, unicode"方案", "roadmap")
        ) parsed.cues |= CUE_PLANNING;
        if (_containsEither(prompt, unicode"代码", "code") || _containsEither(prompt, "solidity", unicode"函数")) {
            parsed.cues |= CUE_CODE;
        }

        parsed.explicitTopic = _explicitTopic(prompt);
    }

    function _explicitTopic(bytes memory prompt) private pure returns (uint8) {
        if (
            _containsEither(prompt, "bsc", "bnb smart chain")
                || _containsEither(prompt, unicode"币安智能链", unicode"bnb链")
        ) {
            return TOPIC_BSC;
        }
        if (
            _containsEither(prompt, unicode"人类", "human")
                || _containsEither(prompt, unicode"人是什么", "people")
        ) {
            return TOPIC_HUMAN;
        }
        if (
            _containsEither(prompt, "gas", unicode"燃气费") || _containsEither(prompt, unicode"手续费", "gas fee")
        ) {
            return TOPIC_GAS;
        }
        if (
            _containsEither(prompt, unicode"钱包", "wallet")
                || _containsEither(prompt, unicode"私钥", "private key")
                || _containsEither(prompt, unicode"助记词", "seed phrase")
        ) return TOPIC_WALLET;
        if (
            _containsEither(prompt, unicode"合约", "contract") || _containsEither(prompt, unicode"管理员", "admin")
                || _containsEither(prompt, unicode"增发", "mint") || _containsEither(prompt, unicode"代理", "proxy")
                || _containsEither(prompt, unicode"黑名单", "blacklist")
        ) return TOPIC_CONTRACT;
        if (_containsEither(prompt, unicode"代币", "token") || _containsEither(prompt, unicode"销毁", "tokenomics"))
        {
            return TOPIC_TOKEN;
        }
        if (
            _containsEither(prompt, "defi", "amm") || _containsEither(prompt, unicode"流动性", "liquidity")
                || _containsEither(prompt, unicode"无常损失", "impermanent loss")
        ) return TOPIC_DEFI;
        if (_containsEither(prompt, "nft", unicode"非同质化")) return TOPIC_NFT;
        if (
            _containsEither(prompt, unicode"交易", "transaction") || _containsEither(prompt, "nonce", unicode"回执")
        ) return TOPIC_TRANSACTION;
        if (
            _containsEither(prompt, unicode"隐私", "privacy") || _containsEither(prompt, unicode"匿名", "anonymous")
        ) {
            return TOPIC_PRIVACY;
        }
        if (_containsEither(prompt, unicode"治理", "governance") || _containsEither(prompt, "dao", unicode"多签")) {
            return TOPIC_GOVERNANCE;
        }
        if (
            _containsEither(prompt, unicode"价格", "price") || _containsEither(prompt, unicode"行情", "market")
                || _containsEither(prompt, unicode"会涨", "will it rise")
        ) return TOPIC_MARKET;
        if (
            _containsEither(prompt, unicode"链上", "onchain")
                || _containsEither(prompt, unicode"区块链", "blockchain")
                || _containsEither(prompt, "evm", unicode"没有服务器")
        ) return TOPIC_ONCHAIN;
        if (
            _containsEither(prompt, unicode"你是谁", "who are you")
                || _containsEither(prompt, unicode"你怎么运作", "how do you work")
                || _containsEither(prompt, unicode"什么东西", "your identity")
        ) return TOPIC_IDENTITY;
        return TOPIC_UNKNOWN;
    }

    function _topicFromIntent(uint8 intent, ParseState memory parsed) private pure returns (uint8) {
        if (intent == UNKNOWN_INTENT || intent == FOLLOWUP_INTENT) return TOPIC_UNKNOWN;
        if (intent == 0 || intent == 17 || (intent >= 18 && intent <= 21)) return TOPIC_DIALOGUE;
        if (intent == 1 || intent == 2 || intent == 23) return TOPIC_IDENTITY;
        if (intent == 3) return TOPIC_ONCHAIN;
        if (intent == 4) return TOPIC_MARKET;
        if (intent == 5 || intent == 6) return TOPIC_CONTRACT;
        if (intent == 7) return TOPIC_TOKEN;
        if (intent == 8) return TOPIC_DEFI;
        if (intent == 9) return TOPIC_NFT;
        if (intent == 10) return TOPIC_WALLET;
        if (intent == 11) return TOPIC_TRANSACTION;
        if (intent == 12) return TOPIC_GAS;
        if (intent == 13 && (parsed.cues & CUE_CODE) != 0) return TOPIC_CONTRACT;
        if ((intent == 15 || intent == 16) && (parsed.cues & CUE_PLANNING) != 0) return TOPIC_PLANNING;
        if (intent == 22) return TOPIC_PRIVACY;
        if (intent == 24) return TOPIC_GOVERNANCE;
        return TOPIC_UNKNOWN;
    }

    function _matchScore(uint16 classifierConfidence, bool explicitTopic, uint8 topic) private pure returns (uint16) {
        if (topic == TOPIC_UNKNOWN) return 0;
        uint256 score = classifierConfidence;
        if (explicitTopic) score += 2_000;
        if (score > 9_500) score = 9_500;
        // score is capped at 9,500 above, safely below uint16.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(score);
    }

    function _traceWord(uint8 opcode, uint8 first, uint8 second, uint16 score, uint64 data, uint64 extra)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            uint256(opcode) << 248 | uint256(first) << 240 | uint256(second) << 232 | uint256(score) << 216
                | uint256(data) << 152 | uint256(extra) << 88
        );
    }

    function _validate(string calldata prompt) private pure {
        uint256 length = bytes(prompt).length;
        if (length == 0) revert EmptyPrompt();
        if (length > MAX_PROMPT_BYTES) revert PromptTooLong(length);
    }

    function _containsEither(bytes memory input, string memory first, string memory second)
        private
        pure
        returns (bool)
    {
        return _contains(input, bytes(first), true) || _contains(input, bytes(second), true);
    }

    function _contains(bytes memory haystack, bytes memory needle, bool asciiInsensitive) private pure returns (bool) {
        if (needle.length == 0 || needle.length > haystack.length) return false;
        for (uint256 start; start + needle.length <= haystack.length; ++start) {
            bool same = true;
            for (uint256 index; index < needle.length; ++index) {
                uint8 left = uint8(haystack[start + index]);
                uint8 right = uint8(needle[index]);
                if (asciiInsensitive) {
                    if (left >= 65 && left <= 90) left += 32;
                    if (right >= 65 && right <= 90) right += 32;
                }
                if (left != right) {
                    same = false;
                    break;
                }
            }
            if (same) return true;
        }
        return false;
    }

    function _hasCjk(bytes memory input) private pure returns (bool) {
        for (uint256 index; index < input.length; ++index) {
            if (uint8(input[index]) >= 0xE3) return true;
        }
        return false;
    }
}
