// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";

import {IBrainEngine} from "./IBrainEngine.sol";

/// @notice Append-only catalogue of TinyAI brain engines.
/// @dev Publishing a new brain never changes an old version. AI owners opt into migrations.
contract TinyAIBrainRegistry is Ownable2Step {
    struct BrainVersion {
        address engine;
        bytes32 codeHash;
        uint64 publishedAt;
        bool enabledForUpgrade;
        string label;
    }

    uint32 public latestVersion;
    uint32 public recommendedVersion;
    mapping(uint32 version => BrainVersion release) private _versions;

    event BrainPublished(uint32 indexed version, address indexed engine, bytes32 codeHash, string label);
    event UpgradeAvailabilityChanged(uint32 indexed version, bool enabled);
    event RecommendedVersionChanged(uint32 indexed previousVersion, uint32 indexed nextVersion);

    error InvalidEngine();
    error InvalidVersion(uint32 version);
    error InvalidLabel();
    error EngineIntegrityFailed(uint32 version);
    error UpgradeDisabled(uint32 version);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function publish(address engine, string calldata label, bool makeRecommended)
        external
        onlyOwner
        returns (uint32 version)
    {
        if (engine.code.length == 0 || bytes(label).length == 0 || bytes(label).length > 64) {
            revert InvalidEngine();
        }
        version = latestVersion + 1;
        IBrainEngine candidate = IBrainEngine(engine);
        if (candidate.engineVersion() != version || !candidate.integrityOk()) revert InvalidEngine();

        bytes32 codeHash = engine.codehash;
        _versions[version] = BrainVersion({
            engine: engine,
            codeHash: codeHash,
            publishedAt: uint64(block.timestamp),
            enabledForUpgrade: true,
            label: label
        });
        latestVersion = version;
        emit BrainPublished(version, engine, codeHash, label);

        if (makeRecommended || recommendedVersion == 0) {
            uint32 previous = recommendedVersion;
            recommendedVersion = version;
            emit RecommendedVersionChanged(previous, version);
        }
    }

    function setUpgradeEnabled(uint32 version, bool enabled) external onlyOwner {
        BrainVersion storage release = _requireVersion(version);
        release.enabledForUpgrade = enabled;
        emit UpgradeAvailabilityChanged(version, enabled);
    }

    function setRecommendedVersion(uint32 version) external onlyOwner {
        BrainVersion storage release = _requireVersion(version);
        if (!release.enabledForUpgrade) revert UpgradeDisabled(version);
        uint32 previous = recommendedVersion;
        recommendedVersion = version;
        emit RecommendedVersionChanged(previous, version);
    }

    function versionInfo(uint32 version) external view returns (BrainVersion memory) {
        BrainVersion storage release = _requireVersion(version);
        return release;
    }

    function upgradeEnabled(uint32 version) external view returns (bool) {
        return _requireVersion(version).enabledForUpgrade;
    }

    /// @notice Resolves a published engine and rechecks both bytecode identity and its locked dependencies.
    /// @dev Old versions remain callable even when disabled for new upgrades.
    function engineFor(uint32 version) external view returns (IBrainEngine engine) {
        BrainVersion storage release = _requireVersion(version);
        if (release.engine.codehash != release.codeHash || !IBrainEngine(release.engine).integrityOk()) {
            revert EngineIntegrityFailed(version);
        }
        return IBrainEngine(release.engine);
    }

    function _requireVersion(uint32 version) private view returns (BrainVersion storage release) {
        release = _versions[version];
        if (release.engine == address(0)) revert InvalidVersion(version);
    }
}
