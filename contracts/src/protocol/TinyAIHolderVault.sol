// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @notice Receives Flap quote-asset tax revenue and allocates it equally to registered TinyAI NFTs.
/// @dev Rewards attach to each AI identity. Transferring an AI also transfers its unclaimed rewards.
///      New AIs are checkpointed at registration and cannot claim rewards allocated before their birth.
///      `rewardToken == address(0)` selects native BNB; otherwise it selects that ERC-20.
contract TinyAIHolderVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant ACCURACY = 1e24;

    IERC20 public immutable rewardToken;
    address public protocol;
    uint256 public registeredAICount;
    uint256 public accumulatedRewardPerAI;
    uint256 public pendingRewards;
    uint256 public unallocatedRewards;
    uint256 public accountedBalance;
    uint256 public totalReceived;
    uint256 public totalClaimed;

    mapping(uint256 aiId => uint256 accumulatedRewardPerAIPaid) public rewardPerAIPaid;

    event ProtocolBound(address indexed protocol);
    event AIRegistered(uint256 indexed aiId, uint256 accumulatedRewardPerAI);
    event RewardsSynced(uint256 received, uint256 allocated, uint256 pending, uint256 accumulatedRewardPerAI);
    event RewardsUnallocated(uint256 amount);
    event RewardClaimed(address indexed owner, address indexed recipient, uint256 amount, uint256[] aiIds);

    error InvalidAddress();
    error ProtocolAlreadyBound();
    error OnlyProtocol();
    error UnexpectedAIId(uint256 expected, uint256 received);
    error NotAIOwner(uint256 aiId);
    error NothingToClaim();
    error BalanceInvariant(uint256 expectedMinimum, uint256 actual);
    error UnsupportedRewardToken(uint256 expected, uint256 received);
    error UnexpectedNativeValue();

    constructor(IERC20 rewardToken_, address initialOwner) Ownable(initialOwner) {
        if (address(rewardToken_) != address(0) && address(rewardToken_).code.length == 0) revert InvalidAddress();
        rewardToken = rewardToken_;
    }

    function isNativeReward() external view returns (bool) {
        return address(rewardToken) == address(0);
    }

    /// @notice One-time binding to the Token Mode AI protocol.
    function bindProtocol(address protocol_) external onlyOwner {
        if (protocol != address(0)) revert ProtocolAlreadyBound();
        if (protocol_.code.length == 0) revert InvalidAddress();
        protocol = protocol_;
        emit ProtocolBound(protocol_);
    }

    /// @notice Registers the next sequential AI and checkpoints it after all earlier rewards.
    function registerAI(uint256 aiId) external {
        if (msg.sender != protocol) revert OnlyProtocol();
        uint256 expected = registeredAICount + 1;
        if (aiId != expected) revert UnexpectedAIId(expected, aiId);

        _sync();
        registeredAICount = aiId;
        rewardPerAIPaid[aiId] = accumulatedRewardPerAI;
        uint256 allocated = _distributePending();

        emit AIRegistered(aiId, accumulatedRewardPerAI);
        if (allocated != 0) emit RewardsSynced(0, allocated, pendingRewards, accumulatedRewardPerAI);
    }

    /// @notice Accounts any reward tokens transferred to this Vault.
    function sync() external nonReentrant returns (uint256 received, uint256 allocated) {
        return _sync();
    }

    /// @notice Claims all rewards attached to AI IDs currently owned by the caller.
    function claim(uint256[] calldata aiIds, address recipient) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) revert InvalidAddress();
        _sync();

        uint256 checkpoint = accumulatedRewardPerAI;
        uint256 length = aiIds.length;
        for (uint256 index; index < length; ++index) {
            uint256 aiId = aiIds[index];
            if (IERC721(protocol).ownerOf(aiId) != msg.sender) revert NotAIOwner(aiId);
            uint256 paid = rewardPerAIPaid[aiId];
            if (checkpoint > paid) {
                uint256 aiAmount = (checkpoint - paid) / ACCURACY;
                if (aiAmount != 0) {
                    amount += aiAmount;
                    // Preserve sub-unit carry instead of discarding it at every claim.
                    rewardPerAIPaid[aiId] = paid + aiAmount * ACCURACY;
                }
            }
        }
        if (amount == 0) revert NothingToClaim();

        accountedBalance -= amount;
        totalClaimed += amount;
        if (address(rewardToken) == address(0)) {
            (bool sent,) = payable(recipient).call{value: amount}("");
            if (!sent) revert UnsupportedRewardToken(amount, 0);
        } else {
            uint256 recipientBefore = rewardToken.balanceOf(recipient);
            rewardToken.safeTransfer(recipient, amount);
            uint256 recipientAfter = rewardToken.balanceOf(recipient);
            uint256 received = recipientAfter >= recipientBefore ? recipientAfter - recipientBefore : 0;
            if (received != amount) revert UnsupportedRewardToken(amount, received);
        }

        emit RewardClaimed(msg.sender, recipient, amount, aiIds);
    }

    function claimable(uint256 aiId) external view returns (uint256) {
        if (aiId == 0 || aiId > registeredAICount) return 0;
        uint256 preview = _previewAccumulatedRewardPerAI();
        uint256 paid = rewardPerAIPaid[aiId];
        return preview > paid ? (preview - paid) / ACCURACY : 0;
    }

    function claimableMany(uint256[] calldata aiIds) external view returns (uint256 amount) {
        uint256 preview = _previewAccumulatedRewardPerAI();
        uint256 length = aiIds.length;
        for (uint256 index; index < length; ++index) {
            uint256 aiId = aiIds[index];
            if (aiId == 0 || aiId > registeredAICount) continue;
            uint256 paid = rewardPerAIPaid[aiId];
            if (preview > paid) amount += (preview - paid) / ACCURACY;
        }
    }

    /// @dev Native-tax transfers arrive with value. ERC-20 TaxProcessor transfers first, then sends a zero-value ping.
    receive() external payable nonReentrant {
        if (address(rewardToken) != address(0) && msg.value != 0) revert UnexpectedNativeValue();
        _sync();
    }

    function _sync() private returns (uint256 received, uint256 allocated) {
        uint256 balance = _rewardBalance();
        if (balance < accountedBalance) revert BalanceInvariant(accountedBalance, balance);
        received = balance - accountedBalance;
        if (received != 0) {
            accountedBalance = balance;
            totalReceived += received;
            if (registeredAICount == 0) {
                // Revenue that predates the first AI cannot belong to a future owner.
                unallocatedRewards += received;
                emit RewardsUnallocated(received);
            } else {
                pendingRewards += received;
            }
        }
        allocated = _distributePending();
        if (received != 0 || allocated != 0) {
            emit RewardsSynced(received, allocated, pendingRewards, accumulatedRewardPerAI);
        }
    }

    function _distributePending() private returns (uint256 allocated) {
        uint256 count = registeredAICount;
        uint256 pending = pendingRewards;
        if (count == 0 || pending == 0) return 0;
        uint256 increment = Math.mulDiv(pending, ACCURACY, count);
        if (increment == 0) return 0;
        // Once converted into the per-AI accumulator, the whole pending amount must leave
        // the queue. Keeping the integer rounding remainder in `pendingRewards` would let a
        // later `sync()` convert the same value a second time. Per-AI sub-unit carry remains
        // in `accumulatedRewardPerAI - rewardPerAIPaid[aiId]` until future rewards make it
        // claimable, while aggregate claims can never exceed the real Vault balance.
        allocated = pending;
        accumulatedRewardPerAI += increment;
        pendingRewards = 0;
    }

    function _previewAccumulatedRewardPerAI() private view returns (uint256 preview) {
        preview = accumulatedRewardPerAI;
        uint256 balance = _rewardBalance();
        if (balance < accountedBalance) revert BalanceInvariant(accountedBalance, balance);
        uint256 pending = pendingRewards + (balance - accountedBalance);
        if (registeredAICount != 0 && pending != 0) {
            preview += Math.mulDiv(pending, ACCURACY, registeredAICount);
        }
    }

    function _rewardBalance() private view returns (uint256) {
        return address(rewardToken) == address(0) ? address(this).balance : rewardToken.balanceOf(address(this));
    }
}
