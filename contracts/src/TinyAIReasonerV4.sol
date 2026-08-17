// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TinyAIKnowledgeV4} from "./TinyAIKnowledgeV4.sol";

/// @notice TinyAI v4.1 research core: bounded language routing, fact retrieval,
///         forward-chaining rules, verification, universal composition, and wallet memory in the EVM.
/// @dev Every accepted prompt receives an answer, but this is deliberately not an open-ended LLM.
///      Every reasoning step is bounded and returned as a packed trace word for replay.
contract TinyAIReasonerV4 {
    uint8 public constant VERSION = 4;
    uint8 public constant QUICK_DEPTH = 0;
    uint8 public constant DEEP_DEPTH = 1;
    uint8 public constant MAX_TRACE_STEPS = 12;
    uint8 public constant RULE_COUNT = 18;
    uint256 public constant MAX_PROMPT_BYTES = 280;
    bytes32 public constant KNOWLEDGE_HASH =
        keccak256("TinyAI-v4.1|universal-router|facts-v1|forward-rules-v1|candidate-verifier|prompt-compositor");

    uint8 public constant DOMAIN_UNKNOWN = 0;
    uint8 public constant DOMAIN_IDENTITY = 1;
    uint8 public constant DOMAIN_AI = 2;
    uint8 public constant DOMAIN_HUMAN = 3;
    uint8 public constant DOMAIN_BSC = 4;
    uint8 public constant DOMAIN_BLOCKCHAIN = 5;
    uint8 public constant DOMAIN_GAS = 6;
    uint8 public constant DOMAIN_WALLET = 7;
    uint8 public constant DOMAIN_TOKEN = 8;
    uint8 public constant DOMAIN_CONTRACT_SECURITY = 9;

    uint8 public constant QUERY_UNKNOWN = 0;
    uint8 public constant QUERY_GREETING = 1;
    uint8 public constant QUERY_DEFINE = 2;
    uint8 public constant QUERY_WHY = 3;
    uint8 public constant QUERY_HOW = 4;
    uint8 public constant QUERY_COMPARE = 5;
    uint8 public constant QUERY_RISK = 6;
    uint8 public constant QUERY_FOLLOWUP = 7;

    uint8 public constant OP_PARSE = 1;
    uint8 public constant OP_LOAD_FACTS = 2;
    uint8 public constant OP_APPLY_RULE = 3;
    uint8 public constant OP_VERIFY = 4;
    uint8 public constant OP_RENDER = 5;

    uint64 public constant FACT_AI = uint64(1) << 0;
    uint64 public constant FACT_HUMAN = uint64(1) << 1;
    uint64 public constant FACT_BSC = uint64(1) << 2;
    uint64 public constant FACT_BLOCKCHAIN = uint64(1) << 3;
    uint64 public constant FACT_GAS = uint64(1) << 4;
    uint64 public constant FACT_WALLET = uint64(1) << 5;
    uint64 public constant FACT_TOKEN = uint64(1) << 6;
    uint64 public constant FACT_CONTRACT = uint64(1) << 7;
    uint64 public constant FACT_EVM = uint64(1) << 8;
    uint64 public constant FACT_BNB_GAS = uint64(1) << 9;
    uint64 public constant FACT_SMART_CONTRACT = uint64(1) << 10;
    uint64 public constant FACT_RESOURCE_BUDGET = uint64(1) << 11;
    uint64 public constant FACT_SCALE_CHANGE = uint64(1) << 12;
    uint64 public constant FACT_ALGORITHM_DEPENDENT = uint64(1) << 13;
    uint64 public constant FACT_ONCHAIN_EXECUTION = uint64(1) << 14;
    uint64 public constant FACT_IMMUTABLE_MODEL = uint64(1) << 15;
    uint64 public constant FACT_NO_INFERENCE_SERVER = uint64(1) << 16;
    uint64 public constant FACT_DETERMINISTIC = uint64(1) << 17;
    uint64 public constant FACT_BIOLOGICAL = uint64(1) << 18;
    uint64 public constant FACT_SOCIAL = uint64(1) << 19;
    uint64 public constant FACT_REASONING = uint64(1) << 20;
    uint64 public constant FACT_PRIVATE_KEY = uint64(1) << 21;
    uint64 public constant FACT_SIGNATURE = uint64(1) << 22;
    uint64 public constant FACT_MINTABLE = uint64(1) << 23;
    uint64 public constant FACT_ADMIN = uint64(1) << 24;
    uint64 public constant FACT_PROXY = uint64(1) << 25;
    uint64 public constant FACT_BLACKLIST = uint64(1) << 26;
    uint64 public constant FACT_FIXED_REPLY = uint64(1) << 27;
    uint64 public constant FACT_KNOWLEDGE = uint64(1) << 28;
    uint64 public constant FACT_LOW_CONFIDENCE = uint64(1) << 29;
    uint64 public constant FACT_OPEN_WORLD = uint64(1) << 30;
    uint64 public constant FACT_PROMPT_CONDITIONED = uint64(1) << 31;

    uint64 public constant CONCLUSION_BSC_EVM = uint64(1) << 0;
    uint64 public constant CONCLUSION_BSC_USES_BNB = uint64(1) << 1;
    uint64 public constant CONCLUSION_BSC_PROGRAMMABLE = uint64(1) << 2;
    uint64 public constant CONCLUSION_HUMAN_BIOSOCIAL = uint64(1) << 3;
    uint64 public constant CONCLUSION_GAS_NOT_INTELLIGENCE = uint64(1) << 4;
    uint64 public constant CONCLUSION_ARCHITECTURE_MATTERS = uint64(1) << 5;
    uint64 public constant CONCLUSION_ONCHAIN_VERIFIABLE = uint64(1) << 6;
    uint64 public constant CONCLUSION_SUPPLY_RISK = uint64(1) << 7;
    uint64 public constant CONCLUSION_UPGRADE_RISK = uint64(1) << 8;
    uint64 public constant CONCLUSION_PROTECT_KEY = uint64(1) << 9;
    uint64 public constant CONCLUSION_VERIFY_SIGNATURE = uint64(1) << 10;
    uint64 public constant CONCLUSION_AI_BOUNDED = uint64(1) << 12;
    uint64 public constant CONCLUSION_SPECULATIVE_ANSWER = uint64(1) << 13;

    struct Memory {
        uint32 turns;
        uint8 lastDomain;
        uint8 lastQuery;
        uint16 confidence;
        bytes32 rollingContext;
    }

    struct ReasoningResult {
        string response;
        uint8 domain;
        uint8 queryType;
        uint16 confidence;
        uint8 depth;
        uint8 stepCount;
        uint64 facts;
        uint64 conclusions;
        bytes32 traceHash;
        bytes32 nextContext;
        bool chinese;
        bool followedContext;
        bytes32[12] trace;
    }

    struct ParseState {
        uint16[10] domainScores;
        uint8 domain;
        uint8 queryType;
        uint16 confidence;
        uint16 recognized;
        bool chinese;
        bool explicitFollowup;
    }

    struct Work {
        uint64 facts;
        uint64 conclusions;
        uint8 stepCount;
        bytes32[12] trace;
    }

    struct Rule {
        uint64 requireAll;
        uint64 requireAny;
        uint64 forbid;
        uint64 addFacts;
        uint64 addConclusions;
    }

    mapping(address user => Memory memoryState) private _memories;
    uint64 public totalChats;
    TinyAIKnowledgeV4 public immutable knowledge;
    bytes32 public immutable knowledgeCodeHash;

    event ReasonedChat(
        address indexed user,
        uint32 indexed turn,
        uint8 indexed domain,
        uint8 queryType,
        uint16 confidence,
        uint8 depth,
        uint8 stepCount,
        uint64 facts,
        uint64 conclusions,
        string prompt,
        string response,
        bytes32 traceHash,
        bytes32 contextHash,
        bool followedContext,
        bytes32[12] trace
    );

    error EmptyPrompt();
    error PromptTooLong(uint256 length);
    error InvalidDepth(uint8 depth);
    error InvalidKnowledge();

    constructor(TinyAIKnowledgeV4 knowledge_) {
        if (address(knowledge_) == address(0) || knowledge_.KNOWLEDGE_HASH() != KNOWLEDGE_HASH) {
            revert InvalidKnowledge();
        }
        knowledge = knowledge_;
        knowledgeCodeHash = address(knowledge_).codehash;
    }

    function architecture() external pure returns (string memory) {
        return
            "universal language router -> immutable facts -> forward rules -> verifier -> prompt-conditioned compositor";
    }

    function truthBoundary() external pure returns (string memory) {
        return "knowledge authored off-chain; parsing, retrieval, derivation, verification, rendering, and memory execute on-chain";
    }

    function memoryOf(address user) external view returns (Memory memory) {
        return _memories[user];
    }

    function integrityOk() external view returns (bool) {
        return knowledge.KNOWLEDGE_HASH() == KNOWLEDGE_HASH && address(knowledge).codehash == knowledgeCodeHash;
    }

    function preview(address user, string calldata prompt, uint8 depth) external view returns (ReasoningResult memory) {
        _validate(prompt, depth);
        return _reason(user, bytes(prompt), depth, _memories[user]);
    }

    function chat(string calldata prompt, uint8 depth) external returns (ReasoningResult memory result) {
        _validate(prompt, depth);
        Memory memory prior = _memories[msg.sender];
        result = _reason(msg.sender, bytes(prompt), depth, prior);
        uint32 turn = prior.turns + 1;
        _memories[msg.sender] = Memory({
            turns: turn,
            lastDomain: result.domain,
            lastQuery: result.queryType,
            confidence: result.confidence,
            rollingContext: result.nextContext
        });
        totalChats += 1;
        emit ReasonedChat(
            msg.sender,
            turn,
            result.domain,
            result.queryType,
            result.confidence,
            depth,
            result.stepCount,
            result.facts,
            result.conclusions,
            prompt,
            result.response,
            result.traceHash,
            result.nextContext,
            result.followedContext,
            result.trace
        );
    }

    function decodeTraceWord(bytes32 word)
        external
        pure
        returns (
            uint8 opcode,
            uint8 ruleId,
            uint8 domain,
            uint8 queryType,
            uint16 confidence,
            uint64 facts,
            uint64 conclusions
        )
    {
        uint256 packed = uint256(word);
        // forge-lint: disable-next-line(unsafe-typecast)
        opcode = uint8(packed >> 248);
        // forge-lint: disable-next-line(unsafe-typecast)
        ruleId = uint8(packed >> 240);
        // forge-lint: disable-next-line(unsafe-typecast)
        domain = uint8(packed >> 232);
        // forge-lint: disable-next-line(unsafe-typecast)
        queryType = uint8(packed >> 224);
        // forge-lint: disable-next-line(unsafe-typecast)
        confidence = uint16(packed >> 208);
        // forge-lint: disable-next-line(unsafe-typecast)
        facts = uint64(packed >> 144);
        // forge-lint: disable-next-line(unsafe-typecast)
        conclusions = uint64(packed >> 80);
    }

    function _reason(address user, bytes memory prompt, uint8 depth, Memory memory prior)
        private
        view
        returns (ReasoningResult memory result)
    {
        ParseState memory parsed = _parse(prompt);
        bool followedContext = parsed.explicitFollowup && prior.turns != 0 && prior.lastDomain != DOMAIN_UNKNOWN;
        if (followedContext) {
            parsed.domain = prior.lastDomain;
            parsed.queryType = QUERY_FOLLOWUP;
            if (parsed.confidence < 7_000) parsed.confidence = 7_000;
        }

        Work memory work;
        _record(work, OP_PARSE, type(uint8).max, parsed.domain, parsed.queryType, parsed.confidence);
        work.facts = _loadFacts(prompt, parsed);
        if (parsed.domain == DOMAIN_UNKNOWN || parsed.confidence < 4_500) {
            work.facts |= FACT_LOW_CONFIDENCE;
        }
        _record(work, OP_LOAD_FACTS, parsed.domain, parsed.domain, parsed.queryType, parsed.confidence);

        uint8 passLimit = depth == DEEP_DEPTH ? 4 : 1;
        for (uint8 pass; pass < passLimit; ++pass) {
            bool changed;
            for (uint8 ruleId; ruleId < RULE_COUNT; ++ruleId) {
                Rule memory rule = _rule(ruleId);
                if (!_matches(rule, work.facts)) continue;
                uint64 nextFacts = work.facts | rule.addFacts;
                uint64 nextConclusions = work.conclusions | rule.addConclusions;
                if (nextFacts == work.facts && nextConclusions == work.conclusions) continue;
                work.facts = nextFacts;
                work.conclusions = nextConclusions;
                changed = true;
                if (work.stepCount < MAX_TRACE_STEPS - 2) {
                    _record(work, OP_APPLY_RULE, ruleId, parsed.domain, parsed.queryType, parsed.confidence);
                }
            }
            if (!changed) break;
        }

        _record(work, OP_VERIFY, _verificationCode(work), parsed.domain, parsed.queryType, parsed.confidence);
        string memory response = knowledge.render(
            parsed.chinese, parsed.domain, parsed.queryType, depth, work.conclusions, string(prompt), keccak256(prompt)
        );
        _record(work, OP_RENDER, _renderCode(parsed.domain), parsed.domain, parsed.queryType, parsed.confidence);

        bytes32 traceHash = keccak256(
            abi.encode(
                KNOWLEDGE_HASH,
                user,
                prior.rollingContext,
                keccak256(prompt),
                depth,
                parsed.domain,
                parsed.queryType,
                parsed.confidence,
                work.facts,
                work.conclusions,
                work.stepCount,
                work.trace
            )
        );
        bytes32 nextContext = keccak256(
            abi.encodePacked(
                prior.rollingContext,
                keccak256(prompt),
                keccak256(bytes(response)),
                parsed.domain,
                parsed.queryType,
                work.conclusions,
                traceHash
            )
        );
        return ReasoningResult({
            response: response,
            domain: parsed.domain,
            queryType: parsed.queryType,
            confidence: parsed.confidence,
            depth: depth,
            stepCount: work.stepCount,
            facts: work.facts,
            conclusions: work.conclusions,
            traceHash: traceHash,
            nextContext: nextContext,
            chinese: parsed.chinese,
            followedContext: followedContext,
            trace: work.trace
        });
    }

    function _parse(bytes memory prompt) private pure returns (ParseState memory parsed) {
        parsed.chinese = _hasCjk(prompt);

        _scoreIf(parsed, prompt, DOMAIN_IDENTITY, 9, unicode"你是谁", "who are you");
        _scoreIf(parsed, prompt, DOMAIN_IDENTITY, 7, unicode"什么东西", "your identity");
        _scoreIf(parsed, prompt, DOMAIN_AI, 8, unicode"人工智能", "artificial intelligence");
        _scoreIf(parsed, prompt, DOMAIN_AI, 7, "ai", unicode"模型");
        _scoreIf(parsed, prompt, DOMAIN_AI, 6, unicode"聪明", "intelligence");
        _scoreIf(parsed, prompt, DOMAIN_HUMAN, 12, unicode"人类", "human");
        _scoreIf(parsed, prompt, DOMAIN_HUMAN, 8, unicode"人是什么", "people");
        _scoreIf(parsed, prompt, DOMAIN_BSC, 14, "bsc", "bnb smart chain");
        _scoreIf(parsed, prompt, DOMAIN_BSC, 12, unicode"币安智能链", unicode"bnb链");
        _scoreIf(parsed, prompt, DOMAIN_BLOCKCHAIN, 10, unicode"区块链", "blockchain");
        _scoreIf(parsed, prompt, DOMAIN_BLOCKCHAIN, 6, unicode"链上", "onchain");
        _scoreIf(parsed, prompt, DOMAIN_GAS, 13, "gas", unicode"燃气费");
        _scoreIf(parsed, prompt, DOMAIN_GAS, 7, unicode"手续费", unicode"费用");
        _scoreIf(parsed, prompt, DOMAIN_WALLET, 12, unicode"钱包", "wallet");
        _scoreIf(parsed, prompt, DOMAIN_WALLET, 9, unicode"私钥", "private key");
        _scoreIf(parsed, prompt, DOMAIN_TOKEN, 10, unicode"代币", "token");
        _scoreIf(parsed, prompt, DOMAIN_TOKEN, 8, unicode"流动性", "liquidity");
        _scoreIf(parsed, prompt, DOMAIN_CONTRACT_SECURITY, 10, unicode"合约", "contract");
        _scoreIf(parsed, prompt, DOMAIN_CONTRACT_SECURITY, 9, unicode"增发", "mint");
        _scoreIf(parsed, prompt, DOMAIN_CONTRACT_SECURITY, 8, unicode"管理员", "admin");
        _scoreIf(parsed, prompt, DOMAIN_CONTRACT_SECURITY, 8, unicode"代理", "proxy");
        _scoreIf(parsed, prompt, DOMAIN_CONTRACT_SECURITY, 8, unicode"黑名单", "blacklist");

        parsed.explicitFollowup = _containsEither(prompt, unicode"继续说", "tell me more")
            || _containsEither(prompt, unicode"然后呢", "go on")
            || _containsEither(prompt, unicode"详细一点", "more detail")
            || _containsEither(prompt, unicode"再解释", "continue");

        if (parsed.explicitFollowup) {
            parsed.queryType = QUERY_FOLLOWUP;
        } else if (_containsEither(prompt, unicode"你好", "hello") || _containsEither(prompt, unicode"嗨", "hi")) {
            parsed.queryType = QUERY_GREETING;
        } else if (
            _containsEither(prompt, unicode"十倍", "10x") || _containsEither(prompt, unicode"提高", "increase")
                || _containsEither(prompt, unicode"提升", "improve")
                || _containsEither(prompt, unicode"比较", "compare")
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

        uint16 top;
        uint16 second;
        for (uint8 domain = 1; domain < 10; ++domain) {
            uint16 score = parsed.domainScores[domain];
            if (score > top) {
                second = top;
                top = score;
                parsed.domain = domain;
            } else if (score > second) {
                second = score;
            }
        }
        if (top < 5) {
            parsed.domain = DOMAIN_UNKNOWN;
            parsed.confidence = top == 0 ? (parsed.queryType == QUERY_UNKNOWN ? 500 : 1_800) : 3_500;
        } else {
            uint256 confidence = 5_000 + uint256(top - second) * 4_000 / (uint256(top) + second + 1);
            if (confidence > 9_200) confidence = 9_200;
            // forge-lint: disable-next-line(unsafe-typecast)
            parsed.confidence = uint16(confidence);
        }
        if (parsed.queryType == QUERY_UNKNOWN && parsed.domain != DOMAIN_UNKNOWN) parsed.queryType = QUERY_DEFINE;
    }

    function _scoreIf(
        ParseState memory parsed,
        bytes memory prompt,
        uint8 domain,
        uint16 score,
        string memory first,
        string memory second
    ) private pure {
        if (_contains(prompt, bytes(first), true) || _contains(prompt, bytes(second), true)) {
            parsed.domainScores[domain] += score;
            parsed.recognized += 1;
        }
    }

    function _loadFacts(bytes memory prompt, ParseState memory parsed) private pure returns (uint64 facts) {
        if (parsed.domain == DOMAIN_UNKNOWN) facts |= FACT_OPEN_WORLD | FACT_PROMPT_CONDITIONED;
        if (parsed.domainScores[DOMAIN_AI] != 0 || parsed.domain == DOMAIN_AI || parsed.domain == DOMAIN_IDENTITY) {
            facts |= FACT_AI | FACT_REASONING | FACT_KNOWLEDGE;
        }
        if (parsed.domainScores[DOMAIN_HUMAN] != 0 || parsed.domain == DOMAIN_HUMAN) facts |= FACT_HUMAN;
        if (parsed.domainScores[DOMAIN_BSC] != 0 || parsed.domain == DOMAIN_BSC) facts |= FACT_BSC;
        if (parsed.domainScores[DOMAIN_BLOCKCHAIN] != 0 || parsed.domain == DOMAIN_BLOCKCHAIN) {
            facts |= FACT_BLOCKCHAIN;
        }
        if (parsed.domainScores[DOMAIN_GAS] != 0 || parsed.domain == DOMAIN_GAS) {
            facts |= FACT_GAS | FACT_RESOURCE_BUDGET;
        }
        if (parsed.domainScores[DOMAIN_WALLET] != 0 || parsed.domain == DOMAIN_WALLET) facts |= FACT_WALLET;
        if (parsed.domainScores[DOMAIN_TOKEN] != 0 || parsed.domain == DOMAIN_TOKEN) facts |= FACT_TOKEN;
        if (parsed.domainScores[DOMAIN_CONTRACT_SECURITY] != 0 || parsed.domain == DOMAIN_CONTRACT_SECURITY) {
            facts |= FACT_CONTRACT;
        }
        if (
            _containsEither(prompt, unicode"十倍", "10x") || _containsEither(prompt, unicode"提高", "increase")
                || _containsEither(prompt, unicode"提升", "improve")
        ) facts |= FACT_SCALE_CHANGE;
        if (
            _containsEither(prompt, unicode"链上", "onchain") || _containsEither(prompt, "evm", unicode"区块链上")
        ) {
            facts |= FACT_ONCHAIN_EXECUTION | FACT_IMMUTABLE_MODEL | FACT_NO_INFERENCE_SERVER;
        }
        if (_containsEither(prompt, unicode"私钥", "private key") || parsed.domain == DOMAIN_WALLET) {
            facts |= FACT_PRIVATE_KEY;
        }
        if (
            _containsEither(prompt, unicode"签名", "signature") || _containsEither(prompt, unicode"授权", "approve")
        ) {
            facts |= FACT_SIGNATURE;
        }
        if (_containsEither(prompt, unicode"增发", "mint")) facts |= FACT_MINTABLE;
        if (
            _containsEither(prompt, unicode"管理员", "admin") || _containsEither(prompt, "owner", unicode"所有者")
        ) facts |= FACT_ADMIN;
        if (_containsEither(prompt, unicode"代理", "proxy") || _containsEither(prompt, unicode"升级", "upgrade")) {
            facts |= FACT_PROXY;
        }
        if (_containsEither(prompt, unicode"黑名单", "blacklist")) facts |= FACT_BLACKLIST;
    }

    function _rule(uint8 id) private pure returns (Rule memory rule) {
        if (id == 0) return Rule(FACT_BSC, 0, 0, FACT_EVM, 0);
        if (id == 1) return Rule(FACT_BSC, 0, 0, FACT_BNB_GAS, 0);
        if (id == 2) return Rule(FACT_EVM, 0, 0, FACT_SMART_CONTRACT, 0);
        if (id == 3) return Rule(FACT_BSC | FACT_EVM, 0, 0, 0, CONCLUSION_BSC_EVM);
        if (id == 4) return Rule(FACT_BSC | FACT_BNB_GAS, 0, 0, 0, CONCLUSION_BSC_USES_BNB);
        if (id == 5) return Rule(FACT_BSC | FACT_SMART_CONTRACT, 0, 0, 0, CONCLUSION_BSC_PROGRAMMABLE);
        if (id == 6) return Rule(FACT_HUMAN, 0, 0, FACT_BIOLOGICAL, 0);
        if (id == 7) return Rule(FACT_HUMAN, 0, 0, FACT_SOCIAL, 0);
        if (id == 8) {
            return Rule(FACT_HUMAN | FACT_BIOLOGICAL | FACT_SOCIAL, 0, 0, 0, CONCLUSION_HUMAN_BIOSOCIAL);
        }
        if (id == 9) {
            return Rule(
                FACT_RESOURCE_BUDGET | FACT_SCALE_CHANGE | FACT_ALGORITHM_DEPENDENT,
                0,
                0,
                0,
                CONCLUSION_ARCHITECTURE_MATTERS
            );
        }
        if (id == 10) {
            return Rule(
                FACT_GAS | FACT_SCALE_CHANGE | FACT_AI, 0, 0, FACT_ALGORITHM_DEPENDENT, CONCLUSION_GAS_NOT_INTELLIGENCE
            );
        }
        if (id == 11) return Rule(FACT_AI, 0, 0, FACT_FIXED_REPLY, CONCLUSION_AI_BOUNDED);
        if (id == 12) {
            return Rule(
                FACT_AI | FACT_ONCHAIN_EXECUTION | FACT_IMMUTABLE_MODEL | FACT_NO_INFERENCE_SERVER,
                0,
                0,
                FACT_DETERMINISTIC,
                CONCLUSION_ONCHAIN_VERIFIABLE
            );
        }
        if (id == 13) {
            return Rule(FACT_CONTRACT | FACT_MINTABLE | FACT_ADMIN, 0, 0, 0, CONCLUSION_SUPPLY_RISK);
        }
        if (id == 14) {
            return Rule(FACT_CONTRACT | FACT_PROXY | FACT_ADMIN, 0, 0, 0, CONCLUSION_UPGRADE_RISK);
        }
        if (id == 15) return Rule(FACT_WALLET | FACT_PRIVATE_KEY, 0, 0, 0, CONCLUSION_PROTECT_KEY);
        if (id == 16) return Rule(FACT_WALLET | FACT_SIGNATURE, 0, 0, 0, CONCLUSION_VERIFY_SIGNATURE);
        return Rule(FACT_LOW_CONFIDENCE, 0, 0, 0, CONCLUSION_SPECULATIVE_ANSWER);
    }

    function _matches(Rule memory rule, uint64 facts) private pure returns (bool) {
        if ((facts & rule.requireAll) != rule.requireAll) return false;
        if (rule.requireAny != 0 && (facts & rule.requireAny) == 0) return false;
        return rule.forbid == 0 || (facts & rule.forbid) == 0;
    }

    function _record(Work memory work, uint8 opcode, uint8 ruleId, uint8 domain, uint8 queryType, uint16 confidence)
        private
        pure
    {
        if (work.stepCount >= MAX_TRACE_STEPS) return;
        uint256 packed = uint256(opcode) << 248 | uint256(ruleId) << 240 | uint256(domain) << 232 | uint256(queryType)
            << 224 | uint256(confidence) << 208 | uint256(work.facts) << 144 | uint256(work.conclusions) << 80;
        work.trace[work.stepCount] = bytes32(packed);
        work.stepCount += 1;
    }

    function _verificationCode(Work memory work) private pure returns (uint8) {
        if ((work.conclusions & CONCLUSION_SPECULATIVE_ANSWER) != 0) return 3;
        if (work.conclusions == 0) return 1;
        return 0;
    }

    function _renderCode(uint8 domain) private pure returns (uint8) {
        return domain;
    }

    function _validate(string calldata prompt, uint8 depth) private pure {
        uint256 length = bytes(prompt).length;
        if (length == 0) revert EmptyPrompt();
        if (length > MAX_PROMPT_BYTES) revert PromptTooLong(length);
        if (depth > DEEP_DEPTH) revert InvalidDepth(depth);
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
