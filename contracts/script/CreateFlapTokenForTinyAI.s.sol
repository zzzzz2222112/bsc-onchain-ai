// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {TinyAIHolderVault} from "../src/protocol/TinyAIHolderVault.sol";

interface IFlapPortalV6 {
    struct SaltLockEntry {
        address locker;
        uint8 tokenVersion;
    }

    struct NewTokenV6Params {
        string name;
        string symbol;
        string meta;
        uint8 dexThresh;
        bytes32 salt;
        uint8 migratorType;
        address quoteToken;
        uint256 quoteAmt;
        address beneficiary;
        bytes permitData;
        bytes32 extensionID;
        bytes extensionData;
        uint8 dexId;
        uint8 lpFeeProfile;
        uint16 buyTaxRate;
        uint16 sellTaxRate;
        uint64 taxDuration;
        uint64 antiFarmerDuration;
        uint16 mktBps;
        uint16 deflationBps;
        uint16 dividendBps;
        uint16 lpBps;
        uint256 minimumShareBalance;
        address dividendToken;
        address commissionReceiver;
        uint8 tokenVersion;
    }

    function newTokenV6(NewTokenV6Params calldata params) external payable returns (address token);
    function getSaltLock(bytes32 salt) external view returns (SaltLockEntry memory entry);
}

interface ICreatedFlapToken {
    function quoteToken() external view returns (address);
    function taxProcessor() external view returns (address);
}

interface IPrelaunchProtocolView {
    function paymentToken() external view returns (address);
    function holderVault() external view returns (address);
}

/// @notice Step 4: creates the mined Flap payment token after the Vault and TinyAI stack are bound.
/// @dev The configuration deliberately disables the official holder-dividend, burn, LP and commission buckets:
///      100% of Flap's beneficiary allocation goes to HOLDER_VAULT. Flap-level deductions still apply first.
contract CreateFlapTokenForTinyAI is Script {
    using SafeERC20 for IERC20;

    uint256 private constant BSC_CHAIN_ID = 56;
    address private constant DEFAULT_FLAP_PORTAL = 0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0;
    address private constant FLAP_TAX_V3_IMPLEMENTATION = 0x024f18294970B5c76c0691b87f138A0317156422;
    address private constant NVDAB = 0x02Fca66C1D1aFB4E2A7884261eB00F63598a7436;
    uint16 private constant FULL_BPS = 10_000;
    uint256 private constant ERC20_QUOTE_CREATION_VALUE = 1 gwei;
    uint8 private constant DEX_THRESHOLD_FOUR_FIFTHS = 1;
    uint8 private constant MIGRATOR_V2 = 1;
    uint8 private constant DEX_ID_DEFAULT = 0;
    uint8 private constant LP_FEE_STANDARD = 0;
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

        IFlapPortalV6 portal = IFlapPortalV6(vm.envOr("FLAP_PORTAL", DEFAULT_FLAP_PORTAL));
        TinyAIHolderVault holderVault = TinyAIHolderVault(payable(vm.envAddress("HOLDER_VAULT")));
        address expectedToken = vm.envAddress("PAYMENT_TOKEN");
        address quoteToken = vm.envOr("FLAP_QUOTE_TOKEN", NVDAB);
        bytes32 salt = vm.envBytes32("FLAP_TOKEN_SALT");
        uint256 buyTax = vm.envUint("FLAP_BUY_TAX_BPS");
        uint256 sellTax = vm.envUint("FLAP_SELL_TAX_BPS");
        uint256 taxDuration = vm.envUint("FLAP_TAX_DURATION");
        uint256 antiFarmerDuration = vm.envOr("FLAP_ANTI_FARMER_DURATION", uint256(0));
        uint256 quoteAmount = vm.envOr("FLAP_INITIAL_QUOTE_AMOUNT", uint256(0));
        uint256 callValue = vm.envOr("FLAP_CALL_VALUE", ERC20_QUOTE_CREATION_VALUE);
        string memory tokenName = vm.envString("FLAP_TOKEN_NAME");
        string memory tokenSymbol = vm.envString("FLAP_TOKEN_SYMBOL");

        require(address(portal).code.length > 0, "INVALID_FLAP_PORTAL");
        require(quoteToken == NVDAB, "QUOTE_TOKEN_MUST_BE_NVDAB");
        require(expectedToken != address(0) && expectedToken.code.length == 0, "EXPECTED_TOKEN_CA_NOT_EMPTY");
        require(_predict(address(portal), salt) == expectedToken, "SALT_DOES_NOT_MATCH_EXPECTED_CA");
        IFlapPortalV6.SaltLockEntry memory saltLock = portal.getSaltLock(salt);
        require(saltLock.locker == deployer, "SALT_MUST_BE_LOCKED_BY_DEPLOYER");
        require(saltLock.tokenVersion == TOKEN_TAXED_V3, "SALT_LOCK_VERSION_MISMATCH");
        require(address(holderVault).code.length > 0, "INVALID_HOLDER_VAULT");
        require(address(holderVault.rewardToken()) == quoteToken, "VAULT_REWARD_ASSET_MISMATCH");
        address boundProtocol = holderVault.protocol();
        require(boundProtocol.code.length > 0, "HOLDER_VAULT_NOT_BOUND");
        require(IPrelaunchProtocolView(boundProtocol).paymentToken() == expectedToken, "PROTOCOL_PAYMENT_CA_MISMATCH");
        require(IPrelaunchProtocolView(boundProtocol).holderVault() == address(holderVault), "PROTOCOL_VAULT_MISMATCH");
        require(quoteToken.code.length > 0, "INVALID_FLAP_QUOTE_TOKEN");
        require(buyTax > 0 && buyTax <= FULL_BPS, "INVALID_BUY_TAX");
        require(sellTax > 0 && sellTax <= FULL_BPS, "INVALID_SELL_TAX");
        require(taxDuration > 0 && taxDuration <= type(uint64).max, "INVALID_TAX_DURATION");
        require(antiFarmerDuration <= type(uint64).max, "INVALID_ANTI_FARMER_DURATION");
        require(quoteAmount == 0, "INITIAL_QUOTE_AMOUNT_MUST_BE_ZERO");
        require(callValue == ERC20_QUOTE_CREATION_VALUE, "CALL_VALUE_MUST_EQUAL_1_GWEI");
        require(bytes(tokenName).length != 0 && bytes(tokenName).length <= 64, "INVALID_TOKEN_NAME");
        require(bytes(tokenSymbol).length != 0 && bytes(tokenSymbol).length <= 16, "INVALID_TOKEN_SYMBOL");

        IFlapPortalV6.NewTokenV6Params memory params = IFlapPortalV6.NewTokenV6Params({
            name: tokenName,
            symbol: tokenSymbol,
            meta: vm.envOr("FLAP_TOKEN_META", string("")),
            dexThresh: DEX_THRESHOLD_FOUR_FIFTHS,
            salt: salt,
            migratorType: MIGRATOR_V2,
            quoteToken: quoteToken,
            quoteAmt: quoteAmount,
            beneficiary: address(holderVault),
            permitData: bytes(""),
            extensionID: bytes32(0),
            extensionData: bytes(""),
            dexId: DEX_ID_DEFAULT,
            lpFeeProfile: LP_FEE_STANDARD,
            buyTaxRate: uint16(buyTax),
            sellTaxRate: uint16(sellTax),
            taxDuration: uint64(taxDuration),
            antiFarmerDuration: uint64(antiFarmerDuration),
            mktBps: FULL_BPS,
            deflationBps: 0,
            dividendBps: 0,
            lpBps: 0,
            minimumShareBalance: 0,
            dividendToken: quoteToken,
            commissionReceiver: address(0),
            tokenVersion: TOKEN_TAXED_V3
        });

        if (cliSigner) vm.startBroadcast();
        else vm.startBroadcast(privateKey);
        if (quoteToken != address(0) && quoteAmount != 0) {
            IERC20(quoteToken).forceApprove(address(portal), quoteAmount);
        }
        address token = portal.newTokenV6{value: callValue}(params);
        vm.stopBroadcast();

        require(token == expectedToken, "CREATED_TOKEN_CA_MISMATCH");
        require(token.code.length > 0, "FLAP_TOKEN_NOT_DEPLOYED");
        require(ICreatedFlapToken(token).quoteToken() == quoteToken, "CREATED_QUOTE_TOKEN_MISMATCH");
        require(ICreatedFlapToken(token).taxProcessor().code.length > 0, "CREATED_TAX_PROCESSOR_INVALID");

        console2.log("deployer", deployer);
        console2.log("new Flap token", token);
        console2.log("quote/reward asset", quoteToken);
        console2.log("AI holder reward vault", address(holderVault));
        console2.log("buy tax bps", buyTax);
        console2.log("sell tax bps", sellTax);
        console2.log("tax duration seconds", taxDuration);
        console2.log("market/vault allocation bps", FULL_BPS);
        console2.log("commission receiver", address(0));
        console2.log("predeployed TinyAI protocol", boundProtocol);
        console2.log("launch completed: the prebound Token Mode stack is now live");
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
