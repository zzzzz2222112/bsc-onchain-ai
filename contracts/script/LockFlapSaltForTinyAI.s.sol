// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";

interface IFlapSaltLocker {
    struct SaltLockEntry {
        address locker;
        uint8 tokenVersion;
    }

    function SALT_LOCK_FEE() external view returns (uint256);
    function lockSalt(bytes32 salt, uint8 tokenVersion) external payable;
    function getSaltLock(bytes32 salt) external view returns (SaltLockEntry memory entry);
}

/// @notice Step 1b: reserves the mined Tax V3 salt before any public launch transaction.
/// @dev Submit this reservation through a separately verified protected path. The script
///      pins the expected fee so a Portal fee change cannot silently spend more BNB.
contract LockFlapSaltForTinyAI is Script {
    uint256 private constant BSC_CHAIN_ID = 56;
    address private constant DEFAULT_FLAP_PORTAL = 0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0;
    address private constant FLAP_TAX_V3_IMPLEMENTATION = 0x024f18294970B5c76c0691b87f138A0317156422;
    uint8 private constant TOKEN_TAXED_V3 = 6;

    function run() external {
        require(block.chainid == BSC_CHAIN_ID, "BSC_CHAIN_ID_REQUIRED");
        bool cliSigner = vm.envOr("CLI_SIGNER", vm.envOr("UNLOCKED_DEPLOYER", false));
        uint256 privateKey;
        address deployer;
        if (cliSigner) {
            deployer = vm.envAddress("DEPLOYER");
        } else {
            privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            deployer = vm.addr(privateKey);
        }

        IFlapSaltLocker portal = IFlapSaltLocker(vm.envOr("FLAP_PORTAL", DEFAULT_FLAP_PORTAL));
        bytes32 salt = vm.envBytes32("FLAP_TOKEN_SALT");
        address expectedToken = vm.envAddress("PAYMENT_TOKEN");
        uint256 expectedFee = vm.envUint("FLAP_SALT_LOCK_FEE");

        require(address(portal).code.length > 0, "INVALID_FLAP_PORTAL");
        require(expectedToken != address(0) && expectedToken.code.length == 0, "EXPECTED_TOKEN_CA_NOT_EMPTY");
        require(_predict(address(portal), salt) == expectedToken, "SALT_DOES_NOT_MATCH_EXPECTED_CA");
        require(portal.SALT_LOCK_FEE() == expectedFee, "SALT_LOCK_FEE_CHANGED");

        IFlapSaltLocker.SaltLockEntry memory existing = portal.getSaltLock(salt);
        if (existing.locker != address(0)) {
            require(existing.locker == deployer, "SALT_LOCKED_BY_ANOTHER_ADDRESS");
            require(existing.tokenVersion == TOKEN_TAXED_V3, "SALT_LOCKED_FOR_WRONG_VERSION");
            console2.log("salt already reserved by deployer for Tax V3");
            return;
        }

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        portal.lockSalt{value: expectedFee}(salt, TOKEN_TAXED_V3);
        vm.stopBroadcast();

        IFlapSaltLocker.SaltLockEntry memory locked = portal.getSaltLock(salt);
        require(locked.locker == deployer, "SALT_LOCKER_MISMATCH");
        require(locked.tokenVersion == TOKEN_TAXED_V3, "SALT_LOCK_VERSION_MISMATCH");

        console2.log("deployer", deployer);
        console2.log("predicted Flap token", expectedToken);
        console2.log("salt lock fee", expectedFee);
        console2.log("salt reserved for Tax V3");
    }

    function _predict(address portal, bytes32 salt) private pure returns (address predicted) {
        bytes memory proxyCreationCode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            FLAP_TAX_V3_IMPLEMENTATION,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), portal, salt, keccak256(proxyCreationCode)))))
        );
    }
}
