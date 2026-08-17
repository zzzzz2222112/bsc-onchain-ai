// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Deploys arbitrary bytes as immutable runtime code.
/// @dev The resulting address is a data container. Consumers read it with EXTCODECOPY.
contract BytecodeBlob {
    uint256 public constant MAX_PAYLOAD_BYTES = 24_575;

    error EmptyBlob();
    error BlobTooLarge(uint256 length);

    constructor(bytes memory data) {
        if (data.length == 0) revert EmptyBlob();
        if (data.length > MAX_PAYLOAD_BYTES) revert BlobTooLarge(data.length);
        bytes memory runtime = bytes.concat(hex"00", data);
        assembly ("memory-safe") {
            return(add(runtime, 0x20), mload(runtime))
        }
    }
}
