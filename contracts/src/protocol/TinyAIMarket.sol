// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal non-custodial fixed-price market for TinyAI identities and components.
/// @dev BNB is credited to pull-payment balances so buyer callbacks cannot block settlement.
contract TinyAIMarket is ReentrancyGuard {
    uint16 public constant MARKET_FEE_BPS = 0;
    uint8 public constant ASSET_ERC721 = 1;
    uint8 public constant ASSET_ERC1155 = 2;

    address public immutable aiCollection;
    address public immutable componentCollection;

    struct Listing {
        address seller;
        address asset;
        uint256 tokenId;
        uint128 unitPrice;
        uint96 amount;
        uint8 assetKind;
    }

    uint256 public nextListingId = 1;
    mapping(uint256 listingId => Listing listing) public listings;
    mapping(address account => uint256 amount) public owed;

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed asset,
        uint256 tokenId,
        uint96 amount,
        uint128 unitPrice,
        uint8 assetKind
    );
    event Purchased(uint256 indexed listingId, address indexed buyer, uint96 amount, uint256 gross);
    event ListingCancelled(uint256 indexed listingId, address indexed seller);
    event Withdrawal(address indexed account, uint256 amount);

    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error InvalidListing();
    error NotSeller();
    error MissingApproval();
    error IncorrectPayment(uint256 expected, uint256 supplied);
    error NothingToWithdraw();
    error WithdrawalFailed();

    constructor(address initialAICollection, address initialComponentCollection) {
        if (initialAICollection.code.length == 0 || initialComponentCollection.code.length == 0) {
            revert InvalidAddress();
        }
        aiCollection = initialAICollection;
        componentCollection = initialComponentCollection;
    }

    function listAI(address asset, uint256 tokenId, uint128 price) external returns (uint256 listingId) {
        if (asset != aiCollection) revert UnsupportedAsset(asset);
        if (asset.code.length == 0 || price == 0 || IERC721(asset).ownerOf(tokenId) != msg.sender) {
            revert InvalidListing();
        }
        if (
            IERC721(asset).getApproved(tokenId) != address(this)
                && !IERC721(asset).isApprovedForAll(msg.sender, address(this))
        ) {
            revert MissingApproval();
        }
        listingId = _createListing(asset, tokenId, 1, price, ASSET_ERC721);
    }

    function listComponents(address asset, uint256 tokenId, uint96 amount, uint128 unitPrice)
        external
        returns (uint256 listingId)
    {
        if (asset != componentCollection) revert UnsupportedAsset(asset);
        if (
            asset.code.length == 0 || amount == 0 || unitPrice == 0
                || IERC1155(asset).balanceOf(msg.sender, tokenId) < amount
        ) revert InvalidListing();
        if (!IERC1155(asset).isApprovedForAll(msg.sender, address(this))) revert MissingApproval();
        listingId = _createListing(asset, tokenId, amount, unitPrice, ASSET_ERC1155);
    }

    function buy(uint256 listingId, uint96 amount) external payable nonReentrant {
        Listing storage stored = listings[listingId];
        Listing memory listing = stored;
        if (listing.seller == address(0) || amount == 0 || amount > listing.amount) revert InvalidListing();
        if (listing.assetKind == ASSET_ERC721 && amount != 1) revert InvalidListing();

        uint256 gross = uint256(listing.unitPrice) * amount;
        if (msg.value != gross) revert IncorrectPayment(gross, msg.value);
        if (amount == listing.amount) delete listings[listingId];
        else stored.amount = listing.amount - amount;

        owed[listing.seller] += gross;

        if (listing.assetKind == ASSET_ERC721) {
            if (IERC721(listing.asset).ownerOf(listing.tokenId) != listing.seller) revert InvalidListing();
            if (
                IERC721(listing.asset).getApproved(listing.tokenId) != address(this)
                    && !IERC721(listing.asset).isApprovedForAll(listing.seller, address(this))
            ) revert MissingApproval();
            IERC721(listing.asset).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        } else if (listing.assetKind == ASSET_ERC1155) {
            if (
                IERC1155(listing.asset).balanceOf(listing.seller, listing.tokenId) < amount
                    || !IERC1155(listing.asset).isApprovedForAll(listing.seller, address(this))
            ) revert MissingApproval();
            IERC1155(listing.asset).safeTransferFrom(listing.seller, msg.sender, listing.tokenId, amount, "");
        } else {
            revert InvalidListing();
        }
        emit Purchased(listingId, msg.sender, amount, gross);
    }

    function cancel(uint256 listingId) external {
        Listing memory listing = listings[listingId];
        if (listing.seller == address(0)) revert InvalidListing();
        if (listing.seller != msg.sender) revert NotSeller();
        delete listings[listingId];
        emit ListingCancelled(listingId, msg.sender);
    }

    function withdraw() external nonReentrant {
        uint256 amount = owed[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        owed[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert WithdrawalFailed();
        emit Withdrawal(msg.sender, amount);
    }

    function _createListing(address asset, uint256 tokenId, uint96 amount, uint128 unitPrice, uint8 assetKind)
        private
        returns (uint256 listingId)
    {
        listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            asset: asset,
            tokenId: tokenId,
            unitPrice: unitPrice,
            amount: amount,
            assetKind: assetKind
        });
        emit Listed(listingId, msg.sender, asset, tokenId, amount, unitPrice, assetKind);
    }
}
