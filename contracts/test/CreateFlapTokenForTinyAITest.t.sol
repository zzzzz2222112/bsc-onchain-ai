// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CreateFlapTokenForTinyAI, IFlapPortalV6} from "../script/CreateFlapTokenForTinyAI.s.sol";

contract CreateFlapTokenForTinyAIHarness is CreateFlapTokenForTinyAI {
    function validateSaltLock(address locker, uint8 tokenVersion, address deployer, bool requireSaltLock)
        external
        pure
    {
        _validateSaltLock(
            IFlapPortalV6.SaltLockEntry({locker: locker, tokenVersion: tokenVersion}), deployer, requireSaltLock
        );
    }
}

contract CreateFlapTokenForTinyAITest is Test {
    CreateFlapTokenForTinyAIHarness private harness;
    address private constant DEPLOYER = address(0xBEEF);

    function setUp() public {
        harness = new CreateFlapTokenForTinyAIHarness();
    }

    function testUnlockedSaltIsAcceptedOnlyWhenOverrideIsExplicit() public view {
        harness.validateSaltLock(address(0), 0, DEPLOYER, false);
    }

    function testUnlockedSaltIsRejectedByDefault() public {
        vm.expectRevert(bytes("SALT_MUST_BE_LOCKED_BY_DEPLOYER"));
        harness.validateSaltLock(address(0), 0, DEPLOYER, true);
    }

    function testMalformedEmptyLockIsRejectedEvenWithOverride() public {
        vm.expectRevert(bytes("INVALID_EMPTY_SALT_LOCK"));
        harness.validateSaltLock(address(0), 6, DEPLOYER, false);
    }

    function testSaltLockedByAnotherAddressIsAlwaysRejected() public {
        vm.expectRevert(bytes("SALT_LOCKED_BY_ANOTHER_ADDRESS"));
        harness.validateSaltLock(address(0xCAFE), 6, DEPLOYER, false);
    }

    function testDeployerTaxV3LockIsAcceptedInEitherMode() public view {
        harness.validateSaltLock(DEPLOYER, 6, DEPLOYER, true);
        harness.validateSaltLock(DEPLOYER, 6, DEPLOYER, false);
    }

    function testDeployerLockWithWrongVersionIsRejected() public {
        vm.expectRevert(bytes("SALT_LOCK_VERSION_MISMATCH"));
        harness.validateSaltLock(DEPLOYER, 5, DEPLOYER, false);
    }
}
