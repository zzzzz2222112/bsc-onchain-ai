// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {ExactERC20Payment} from "./ExactERC20Payment.sol";

/// @notice Fixed-price TinyAI market settled atomically in one exact-value ERC-20.
/// @dev The seller receives 100% directly; the market never holds proceeds and has no fee administrator.
contract TinyAITokenMarket is ReentrancyGuard, ExactERC20Payment {
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

    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error InvalidListing();
    error NotSeller();
    error MissingApproval();

    constructor(address initialAICollection, address initialComponentCollection, IERC20 paymentToken_)
        ExactERC20Payment(paymentToken_)
    {
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

    function buy(uint256 listingId, uint96 amount) external nonReentrant {
        Listing storage stored = listings[listingId];
        Listing memory listing = stored;
        if (listing.seller == address(0) || amount == 0 || amount > listing.amount) revert InvalidListing();
        if (listing.assetKind == ASSET_ERC721 && amount != 1) revert InvalidListing();

        uint256 gross = uint256(listing.unitPrice) * amount;
        if (amount == listing.amount) delete listings[listingId];
        else stored.amount = listing.amount - amount;

        _collectExact(msg.sender, listing.seller, gross);
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
