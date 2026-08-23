// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Shared exact-value ERC-20 settlement for TinyAI Token Mode.
/// @dev Fee-on-transfer and rebasing settlement tokens are deliberately rejected.
abstract contract ExactERC20Payment {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;

    event TokenPayment(address indexed payer, address indexed recipient, uint256 amount);

    error InvalidPaymentToken();
    error PaymentTokenNotDeployed(address predictedToken);
    error UnsupportedPaymentToken(uint256 expected, uint256 received);

    constructor(IERC20 paymentToken_) {
        // Flap token addresses are CREATE2-predicted before launch. A non-zero future CA is
        // therefore valid at construction time, but no payment can execute until code exists.
        if (address(paymentToken_) == address(0)) revert InvalidPaymentToken();
        paymentToken = paymentToken_;
    }

    function _collectExact(address payer, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        if (address(paymentToken).code.length == 0) revert PaymentTokenNotDeployed(address(paymentToken));
        uint256 beforeBalance = paymentToken.balanceOf(recipient);
        paymentToken.safeTransferFrom(payer, recipient, amount);
        uint256 afterBalance = paymentToken.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert UnsupportedPaymentToken(amount, received);
        emit TokenPayment(payer, recipient, amount);
    }
}
