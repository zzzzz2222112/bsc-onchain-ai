// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {ERC1155} from "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

/// @notice Consumable ERC-1155 modules whose immutable definitions have real protocol effects.
contract TinyAIComponents is ERC1155, Ownable2Step, ReentrancyGuard {
    uint8 public constant EFFECT_MEMORY = 1;
    uint8 public constant EFFECT_PERSONALITY = 2;
    uint8 public constant EFFECT_EXPRESSION = 3;
    uint8 public constant EFFECT_SKILL = 4;
    uint64 public constant MAX_COMPONENT_SUPPLY = 100_000;
    uint128 public constant MINT_PRICE = 0.0001 ether;

    struct ComponentDefinition {
        uint8 effectKind;
        uint8 slot;
        uint16 power;
        uint64 cap;
        uint64 minted;
        uint128 mintPrice;
        bool publicMintEnabled;
        bool exists;
    }

    address public protocol;
    address public treasury;
    uint64 public totalDefinedCap;
    uint64 public totalMinted;
    bool public catalogSealed;
    mapping(uint256 id => ComponentDefinition definition) private _definitions;

    event ProtocolBound(address indexed protocol);
    event TreasuryChanged(address indexed previousTreasury, address indexed nextTreasury);
    event ComponentDefined(uint256 indexed id, uint8 indexed effectKind, uint8 indexed slot, uint16 power, uint64 cap);
    event CatalogSealed(uint64 totalCap);
    event ComponentConsumed(address indexed owner, uint256 indexed id, uint256 amount);

    error InvalidAddress();
    error InvalidDefinition();
    error ComponentAlreadyDefined(uint256 id);
    error UnknownComponent(uint256 id);
    error SupplyCapExceeded(uint256 id);
    error TotalSupplyCapExceeded();
    error CatalogAlreadySealed();
    error CatalogNotComplete(uint64 definedCap);
    error IncorrectPayment(uint256 expected, uint256 supplied);
    error ProtocolAlreadyBound();
    error OnlyProtocol();
    error WithdrawalFailed();

    constructor(string memory baseUri, address initialOwner, address initialTreasury)
        ERC1155(baseUri)
        Ownable(initialOwner)
    {
        if (initialTreasury == address(0)) revert InvalidAddress();
        treasury = initialTreasury;
    }

    function definition(uint256 id) external view returns (ComponentDefinition memory) {
        ComponentDefinition storage item = _definitions[id];
        if (!item.exists) revert UnknownComponent(id);
        return item;
    }

    /// @notice Permanently binds the only protocol allowed to burn components for upgrades.
    function bindProtocol(address protocol_) external onlyOwner {
        if (protocol != address(0)) revert ProtocolAlreadyBound();
        if (protocol_.code.length == 0) revert InvalidAddress();
        protocol = protocol_;
        emit ProtocolBound(protocol_);
    }

    /// @notice Effect kind, slot, power and cap are immutable after this call.
    function defineComponent(uint256 id, uint8 effectKind, uint8 slot, uint16 power, uint64 cap) external onlyOwner {
        if (catalogSealed) revert CatalogAlreadySealed();
        if (_definitions[id].exists) revert ComponentAlreadyDefined(id);
        if (
            id == 0 || effectKind < EFFECT_MEMORY || effectKind > EFFECT_SKILL || power == 0 || cap == 0
                || (effectKind == EFFECT_PERSONALITY && slot > 3) || (effectKind == EFFECT_SKILL && slot > 63)
                || ((effectKind == EFFECT_MEMORY || effectKind == EFFECT_EXPRESSION) && slot != 0)
        ) revert InvalidDefinition();
        uint256 nextDefinedCap = uint256(totalDefinedCap) + cap;
        if (nextDefinedCap > MAX_COMPONENT_SUPPLY) revert TotalSupplyCapExceeded();
        totalDefinedCap = uint64(nextDefinedCap);
        _definitions[id] = ComponentDefinition({
            effectKind: effectKind,
            slot: slot,
            power: power,
            cap: cap,
            minted: 0,
            mintPrice: MINT_PRICE,
            publicMintEnabled: true,
            exists: true
        });
        emit ComponentDefined(id, effectKind, slot, power, cap);
    }

    function sealCatalog() external onlyOwner {
        if (catalogSealed) revert CatalogAlreadySealed();
        if (totalDefinedCap != MAX_COMPONENT_SUPPLY) revert CatalogNotComplete(totalDefinedCap);
        catalogSealed = true;
        emit CatalogSealed(totalDefinedCap);
    }

    function setTreasury(address nextTreasury) external onlyOwner {
        if (nextTreasury == address(0)) revert InvalidAddress();
        address previous = treasury;
        treasury = nextTreasury;
        emit TreasuryChanged(previous, nextTreasury);
    }

    function setURI(string calldata nextUri) external onlyOwner {
        _setURI(nextUri);
    }

    function publicMint(uint256 id, uint64 amount) external payable nonReentrant {
        ComponentDefinition storage item = _requireDefinition(id);
        uint256 expected = uint256(item.mintPrice) * amount;
        if (amount == 0 || msg.value != expected) revert IncorrectPayment(expected, msg.value);
        _mintWithinCap(msg.sender, id, amount);
    }

    function consumeFrom(address from, uint256 id, uint256 amount) external {
        if (msg.sender != protocol) revert OnlyProtocol();
        _requireDefinition(id);
        _burn(from, id, amount);
        emit ComponentConsumed(from, id, amount);
    }

    function withdraw() external nonReentrant {
        if (msg.sender != treasury && msg.sender != owner()) revert InvalidAddress();
        uint256 amount = address(this).balance;
        (bool ok,) = payable(treasury).call{value: amount}("");
        if (!ok) revert WithdrawalFailed();
    }

    function _mintWithinCap(address to, uint256 id, uint64 amount) private {
        ComponentDefinition storage item = _requireDefinition(id);
        if (to == address(0) || amount == 0) revert InvalidDefinition();
        uint256 nextMinted = uint256(item.minted) + amount;
        if (nextMinted > item.cap) revert SupplyCapExceeded(id);
        // Safe because the immutable supply cap is uint64 and was checked above.
        // forge-lint: disable-next-line(unsafe-typecast)
        item.minted = uint64(nextMinted);
        totalMinted += amount;
        _mint(to, id, amount, "");
    }

    function _requireDefinition(uint256 id) private view returns (ComponentDefinition storage item) {
        item = _definitions[id];
        if (!item.exists) revert UnknownComponent(id);
    }
}
