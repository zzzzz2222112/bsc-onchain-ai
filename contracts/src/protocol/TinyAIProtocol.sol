// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {IBrainEngine} from "./IBrainEngine.sol";
import {TinyAIBrainRegistry} from "./TinyAIBrainRegistry.sol";
import {TinyAIComponents} from "./TinyAIComponents.sol";

/// @notice ERC-721 population of small on-chain AIs with owner-chosen brain migrations.
contract TinyAIProtocol is ERC721Enumerable, Ownable2Step, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_AI_SUPPLY = 10_000;
    uint256 public constant MINT_PRICE = 0.0001 ether;
    uint256 public constant MAX_PROMPT_BYTES = 280;
    uint8 public constant MAX_MEMORY_CAPACITY = 8;
    uint8 public constant MAX_EXPRESSION_LEVEL = 2;

    struct AIState {
        bytes32 dna;
        bytes32 memoryRoot;
        uint64 bornAt;
        uint64 experience;
        uint32 brainVersion;
        uint32 turns;
        uint64 skillMask;
        uint8 memoryCapacity;
        uint8 curiosity;
        uint8 empathy;
        uint8 humor;
        uint8 caution;
        uint8 expressionLevel;
        bool autoUpgrade;
        bool brainSealed;
        // Reserved for ABI compatibility. Owner-only rooms always keep this false.
        bool publicChat;
    }

    TinyAIBrainRegistry public immutable brainRegistry;
    TinyAIComponents public immutable components;

    uint256 public nextAIId = 1;
    address public treasury;

    mapping(uint256 aiId => AIState state) private _aiStates;
    mapping(uint256 aiId => string name) private _aiNames;
    mapping(uint256 aiId => mapping(uint8 slot => bytes32 interactionHash)) private _memorySlots;

    event AIBorn(
        uint256 indexed aiId,
        address indexed owner,
        uint32 indexed brainVersion,
        bytes32 dna,
        string name,
        bool autoUpgrade
    );
    event AIChat(
        uint256 indexed aiId,
        address indexed speaker,
        uint32 indexed turn,
        uint32 brainVersion,
        uint8 topic,
        uint8 variant,
        bool unknown,
        bool neuralGenerated,
        string prompt,
        string response,
        bytes32 traceHash,
        bytes32 memoryRoot
    );
    event BrainUpgraded(
        uint256 indexed aiId, uint32 indexed previousVersion, uint32 indexed nextVersion, bool automatic
    );
    event AutoUpgradeChanged(uint256 indexed aiId, bool enabled);
    event BrainSealed(uint256 indexed aiId, uint32 indexed brainVersion);
    event ComponentFused(
        uint256 indexed aiId, uint256 indexed componentId, uint256 amount, uint8 effectKind, uint8 slot, uint16 power
    );
    event TreasuryChanged(address indexed previousTreasury, address indexed nextTreasury);

    error InvalidAddress();
    error InvalidName();
    error EmptyPrompt();
    error PromptTooLong(uint256 length);
    error IncorrectPayment(uint256 expected, uint256 supplied);
    error AISupplyCapReached();
    error NotAIOwner(uint256 aiId);
    error BrainIsSealed(uint256 aiId);
    error InvalidBrainUpgrade(uint32 currentVersion, uint32 requestedVersion);
    error ComponentWouldBeWasted(uint256 componentId);
    error UnsupportedComponentEffect(uint8 effectKind);
    error WithdrawalFailed();

    constructor(
        TinyAIBrainRegistry brainRegistry_,
        TinyAIComponents components_,
        address initialOwner,
        address initialTreasury
    ) ERC721("TinyAI Life", "TAIL") Ownable(initialOwner) {
        if (
            address(brainRegistry_).code.length == 0 || address(components_).code.length == 0
                || initialTreasury == address(0)
        ) revert InvalidAddress();
        brainRegistry = brainRegistry_;
        components = components_;
        treasury = initialTreasury;
    }

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /// @notice Enumerates the current owner's AI IDs for wallet dashboards.
    function tokensOfOwner(address owner_) external view returns (uint256[] memory ids) {
        uint256 count = balanceOf(owner_);
        ids = new uint256[](count);
        for (uint256 index; index < count; ++index) {
            ids[index] = tokenOfOwnerByIndex(owner_, index);
        }
    }

    function mintPrice() external pure returns (uint256) {
        return MINT_PRICE;
    }

    function aiName(uint256 aiId) external view returns (string memory) {
        _requireOwned(aiId);
        return _aiNames[aiId];
    }

    function aiState(uint256 aiId) external view returns (AIState memory) {
        _requireOwned(aiId);
        return _aiStates[aiId];
    }

    function memoryAt(uint256 aiId, uint8 slot) external view returns (bytes32) {
        _requireOwned(aiId);
        if (slot >= _aiStates[aiId].memoryCapacity) return bytes32(0);
        return _memorySlots[aiId][slot];
    }

    function mintAI(string calldata name_, bytes32 seed, bool autoUpgrade)
        external
        payable
        nonReentrant
        returns (uint256 aiId)
    {
        if (nextAIId > MAX_AI_SUPPLY) revert AISupplyCapReached();
        _validateName(name_);
        if (msg.value != MINT_PRICE) revert IncorrectPayment(MINT_PRICE, msg.value);

        uint32 version = brainRegistry.recommendedVersion();
        if (version == 0 || !brainRegistry.upgradeEnabled(version)) revert InvalidBrainUpgrade(0, version);
        brainRegistry.engineFor(version);

        aiId = nextAIId++;
        bytes32 dna = keccak256(
            abi.encode(address(this), block.chainid, msg.sender, aiId, seed, blockhash(block.number - 1), name_)
        );
        _aiNames[aiId] = name_;
        _aiStates[aiId] = AIState({
            dna: dna,
            memoryRoot: bytes32(0),
            bornAt: uint64(block.timestamp),
            experience: 0,
            brainVersion: version,
            turns: 0,
            skillMask: 0,
            memoryCapacity: 1,
            curiosity: _trait(dna, 0),
            empathy: _trait(dna, 1),
            humor: _trait(dna, 2),
            caution: _trait(dna, 3),
            expressionLevel: 0,
            autoUpgrade: autoUpgrade,
            brainSealed: false,
            publicChat: false
        });
        _safeMint(msg.sender, aiId);
        emit AIBorn(aiId, msg.sender, version, dna, name_, autoUpgrade);
    }

    /// @notice Only the current ERC-721 owner can talk to and mutate this AI.
    function chatAI(uint256 aiId, string calldata prompt)
        external
        nonReentrant
        returns (IBrainEngine.BrainOutput memory output)
    {
        _requireAIOwner(aiId);
        _validatePrompt(prompt);
        AIState storage state = _aiStates[aiId];
        if (state.autoUpgrade && !state.brainSealed) {
            uint32 recommended = brainRegistry.recommendedVersion();
            if (recommended > state.brainVersion && brainRegistry.upgradeEnabled(recommended)) {
                brainRegistry.engineFor(recommended);
                uint32 previous = state.brainVersion;
                state.brainVersion = recommended;
                emit BrainUpgraded(aiId, previous, recommended, true);
            }
        }

        output = _infer(aiId, state, msg.sender, prompt, state.brainVersion);
        uint32 turn = state.turns + 1;
        bytes32 interactionHash = keccak256(
            abi.encode(
                state.memoryRoot,
                msg.sender,
                keccak256(bytes(prompt)),
                keccak256(bytes(output.response)),
                output.traceHash,
                block.number
            )
        );
        uint8 slot = uint8((turn - 1) % state.memoryCapacity);
        _memorySlots[aiId][slot] = interactionHash;
        state.turns = turn;
        state.experience += output.unknown ? 1 : 3;
        state.memoryRoot = keccak256(abi.encode(state.memoryRoot, interactionHash, slot, turn));

        emit AIChat(
            aiId,
            msg.sender,
            turn,
            state.brainVersion,
            output.topic,
            output.variant,
            output.unknown,
            output.neuralGenerated,
            prompt,
            output.response,
            output.traceHash,
            state.memoryRoot
        );
    }

    function upgradeBrain(uint256 aiId, uint32 nextVersion) external {
        _requireAIOwner(aiId);
        AIState storage state = _aiStates[aiId];
        if (state.brainSealed) revert BrainIsSealed(aiId);
        if (nextVersion <= state.brainVersion || !brainRegistry.upgradeEnabled(nextVersion)) {
            revert InvalidBrainUpgrade(state.brainVersion, nextVersion);
        }
        brainRegistry.engineFor(nextVersion);
        uint32 previous = state.brainVersion;
        state.brainVersion = nextVersion;
        emit BrainUpgraded(aiId, previous, nextVersion, false);
    }

    function setAutoUpgrade(uint256 aiId, bool enabled) external {
        _requireAIOwner(aiId);
        AIState storage state = _aiStates[aiId];
        if (state.brainSealed && enabled) revert BrainIsSealed(aiId);
        state.autoUpgrade = enabled;
        emit AutoUpgradeChanged(aiId, enabled);
    }

    function sealBrain(uint256 aiId) external {
        _requireAIOwner(aiId);
        AIState storage state = _aiStates[aiId];
        if (state.brainSealed) revert BrainIsSealed(aiId);
        state.brainSealed = true;
        state.autoUpgrade = false;
        emit BrainSealed(aiId, state.brainVersion);
    }

    function fuseComponent(uint256 aiId, uint256 componentId, uint64 amount) external nonReentrant {
        _requireAIOwner(aiId);
        if (amount == 0) revert ComponentWouldBeWasted(componentId);
        TinyAIComponents.ComponentDefinition memory item = components.definition(componentId);
        AIState storage state = _aiStates[aiId];
        uint256 increase = uint256(item.power) * amount;

        if (item.effectKind == components.EFFECT_MEMORY()) {
            if (uint256(state.memoryCapacity) + increase > MAX_MEMORY_CAPACITY) {
                revert ComponentWouldBeWasted(componentId);
            }
        } else if (item.effectKind == components.EFFECT_PERSONALITY()) {
            uint8 current = _personalityAt(state, item.slot);
            if (uint256(current) + increase > 100) revert ComponentWouldBeWasted(componentId);
        } else if (item.effectKind == components.EFFECT_EXPRESSION()) {
            if (uint256(state.expressionLevel) + increase > MAX_EXPRESSION_LEVEL) {
                revert ComponentWouldBeWasted(componentId);
            }
        } else if (item.effectKind == components.EFFECT_SKILL()) {
            if (amount != 1 || (state.skillMask & (uint64(1) << item.slot)) != 0) {
                revert ComponentWouldBeWasted(componentId);
            }
        } else {
            revert UnsupportedComponentEffect(item.effectKind);
        }

        components.consumeFrom(msg.sender, componentId, amount);
        if (item.effectKind == components.EFFECT_MEMORY()) {
            // Safe because the branch above caps the result at MAX_MEMORY_CAPACITY (8).
            // forge-lint: disable-next-line(unsafe-typecast)
            state.memoryCapacity += uint8(increase);
        } else if (item.effectKind == components.EFFECT_PERSONALITY()) {
            // Safe because the branch above caps the resulting trait at 100.
            // forge-lint: disable-next-line(unsafe-typecast)
            _increasePersonality(state, item.slot, uint8(increase));
        } else if (item.effectKind == components.EFFECT_EXPRESSION()) {
            // Safe because the branch above caps the result at MAX_EXPRESSION_LEVEL (2).
            // forge-lint: disable-next-line(unsafe-typecast)
            state.expressionLevel += uint8(increase);
        } else {
            state.skillMask |= uint64(1) << item.slot;
        }
        emit ComponentFused(aiId, componentId, amount, item.effectKind, item.slot, item.power);
    }

    function setTreasury(address nextTreasury) external onlyOwner {
        if (nextTreasury == address(0)) revert InvalidAddress();
        address previous = treasury;
        treasury = nextTreasury;
        emit TreasuryChanged(previous, nextTreasury);
    }

    function withdraw() external nonReentrant {
        if (msg.sender != treasury && msg.sender != owner()) revert InvalidAddress();
        uint256 amount = address(this).balance;
        (bool ok,) = payable(treasury).call{value: amount}("");
        if (!ok) revert WithdrawalFailed();
    }

    function tokenURI(uint256 aiId) public view override returns (string memory) {
        _requireOwned(aiId);
        AIState storage state = _aiStates[aiId];
        string memory id = aiId.toString();
        string memory image = Base64.encode(
            bytes(
                string.concat(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800" viewBox="0 0 800 800">',
                    '<rect width="800" height="800" rx="64" fill="#F0B90B"/>',
                    '<circle cx="400" cy="330" r="180" fill="#121212"/><circle cx="340" cy="310" r="18" fill="#F0B90B"/>',
                    '<circle cx="460" cy="310" r="18" fill="#F0B90B"/><path d="M320 395 Q400 455 480 395" stroke="#F0B90B" stroke-width="18" fill="none"/>',
                    '<text x="400" y="590" text-anchor="middle" font-family="Arial,sans-serif" font-size="52" font-weight="700" fill="#121212">',
                    _aiNames[aiId],
                    '</text><text x="400" y="650" text-anchor="middle" font-family="monospace" font-size="28" fill="#121212">TINYAI #',
                    id,
                    unicode" · BRAIN V",
                    uint256(state.brainVersion).toString(),
                    "</text></svg>"
                )
            )
        );
        bytes memory json = abi.encodePacked(
            '{"name":"',
            _aiNames[aiId],
            unicode" · TinyAI #",
            id,
            '","description":"A small on-chain AI whose brain version, DNA, public memory and evolution live in EVM state.",',
            '"image":"data:image/svg+xml;base64,',
            image,
            '","attributes":[',
            _attribute("Brain Version", state.brainVersion),
            ",",
            _attribute("Turns", state.turns),
            ",",
            _attribute("Memory", state.memoryCapacity),
            ",",
            _attribute("Curiosity", state.curiosity),
            ",",
            _attribute("Empathy", state.empathy),
            ",",
            _attribute("Humor", state.humor),
            ",",
            _attribute("Caution", state.caution),
            ",",
            _attribute("Expression", state.expressionLevel),
            "]} "
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _infer(uint256 aiId, AIState storage state, address speaker, string calldata prompt, uint32 version)
        private
        view
        returns (IBrainEngine.BrainOutput memory)
    {
        IBrainEngine engine = brainRegistry.engineFor(version);
        return engine.infer(
            IBrainEngine.BrainInput({
                aiId: aiId,
                dna: state.dna,
                curiosity: state.curiosity,
                empathy: state.empathy,
                humor: state.humor,
                caution: state.caution,
                expressionLevel: state.expressionLevel,
                skillMask: state.skillMask,
                turns: state.turns,
                memoryRoot: state.memoryRoot,
                speaker: speaker,
                prompt: prompt
            })
        );
    }

    function _requireAIOwner(uint256 aiId) private view {
        if (ownerOf(aiId) != msg.sender) revert NotAIOwner(aiId);
    }

    function _validatePrompt(string calldata prompt) private pure {
        uint256 length = bytes(prompt).length;
        if (length == 0) revert EmptyPrompt();
        if (length > MAX_PROMPT_BYTES) revert PromptTooLong(length);
    }

    function _validateName(string calldata name_) private pure {
        bytes calldata data = bytes(name_);
        if (data.length == 0 || data.length > 32) revert InvalidName();
        for (uint256 index; index < data.length; ++index) {
            bytes1 value = data[index];
            if (
                uint8(value) < 0x20 || value == 0x22 || value == 0x5c || value == 0x3c || value == 0x3e || value == 0x26
            ) revert InvalidName();
        }
    }

    function _trait(bytes32 dna, uint256 offset) private pure returns (uint8) {
        return 32 + (uint8(dna[offset]) % 69);
    }

    function _personalityAt(AIState storage state, uint8 slot) private view returns (uint8) {
        if (slot == 0) return state.curiosity;
        if (slot == 1) return state.empathy;
        if (slot == 2) return state.humor;
        return state.caution;
    }

    function _increasePersonality(AIState storage state, uint8 slot, uint8 increase) private {
        if (slot == 0) state.curiosity += increase;
        else if (slot == 1) state.empathy += increase;
        else if (slot == 2) state.humor += increase;
        else state.caution += increase;
    }

    function _attribute(string memory traitType, uint256 value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', traitType, '","value":', value.toString(), "}");
    }
}
