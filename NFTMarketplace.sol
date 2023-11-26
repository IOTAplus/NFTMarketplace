// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing OpenZeppelin's ERC721 and ERC20 interfaces, ReentrancyGuard, and Ownable contracts
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// NFTMarketplace contract allows listing, buying, and selling of NFTs
contract NFTMarketplace is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structure for listing an NFT
    struct Listing {
        uint256 tokenId; // 32 bytes
        address seller; // 20 bytes
        uint32 price; // 4 byte
        address tokenAddress; // 20 bytes
    }

    struct MarketStatistics {
        uint256 totalVolume;
        uint256 averagePrice;
        uint256 TotalListings;
    }

    modifier onlySeller(uint256 listingId) {
        if (msg.sender != listings[listingId].seller) revert("Only seller");
        _;
    }

    // ERC20 token used for payments
    IERC20 public immutable paymentToken;

    // stores the listings
    mapping(uint256 => Listing) public listings;
    // stores the total volume of seller
    mapping(address => uint256) public totalVolumeBySeller;

    // Marketplace fee in basis points (1% default)
    uint256 public feeBasisPoints = 100;

    uint256 public totalSold;
    uint256 public totalVolume;
    uint256 public totalListings;
    uint256 public totalVolumeSold;

    // Events to log actions on the blockchain
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 price
    );
    event ListingUpdated(uint256 indexed listingId, uint256 price);
    event ListingRemoved(uint256 indexed listingId);
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 price
    );
    event FeeUpdated(uint256 feeBasisPoints);

    // Constructor sets the payment token used by the marketplace
    constructor(address _paymentTokenAddress) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentTokenAddress);
    }

    // Function to create a new listing for an NFT
    function createListing(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        if (_tokenAddress == address(0x0)) revert("Invalid address.");

        // Transfer the NFT to the contract for escrow
        IERC721(_tokenAddress).transferFrom(msg.sender, address(this), _tokenId);

        // Add the new listing to the mapping
        listings[totalListings] = Listing(
            _tokenId, 
            msg.sender, 
            uint32(_price), 
            _tokenAddress
        );

        totalVolume += _price;

        // Emit an event for the new listing
        emit ListingCreated(
            totalListings, 
            msg.sender, 
            _tokenAddress, 
            _tokenId, 
            _price
        );

        totalListings++;
    }

    // Function to update the price of an existing listing
    function updateListing(uint256 _listingId, uint256 _newPrice) external onlySeller(_listingId) {
        // Update the listing price
        listings[_listingId].price = uint32(_newPrice);
        // Emit an event for the listing update
        emit ListingUpdated(_listingId, _newPrice);
    }

    // Function to remove an existing listing
    function removeListing(uint256 _listingId) external nonReentrant onlySeller(_listingId) {
        // Transfer the NFT back to the seller
        IERC721(listings[_listingId].tokenAddress).transferFrom(
            address(this),
            listings[_listingId].seller, 
            listings[_listingId].tokenId
        );

        totalVolume -= listings[_listingId].price;

        // Remove listing
        delete listings[_listingId];

        totalListings--;

        // Emit an event for the listing removal
        emit ListingRemoved(_listingId);
    }

    // Function to buy an NFT from an active listing
    function buyNFT(uint256 _listingId) external nonReentrant {
        if (listings[_listingId].tokenAddress == address(0x0)) revert("Listing does not exist.");

        uint256 price = listings[_listingId].price;

        // Calculate the fee and the amount going to the seller
        uint256 fee = (price * feeBasisPoints) / 10000;
        uint256 sellerAmount = price - fee;

        // Transfer the fee to the marketplace
        paymentToken.safeTransferFrom(msg.sender, address(this), fee);

        // Transfer the payment to the seller
        paymentToken.safeTransferFrom(msg.sender, listings[_listingId].seller, sellerAmount);
        
        // Transfer the NFT to the buyer
        IERC721(listings[_listingId].tokenAddress).transferFrom(
            address(this), 
            msg.sender, 
            listings[_listingId].tokenId
        );

        totalVolumeBySeller[listings[_listingId].seller] += price;
        totalVolumeSold += price;
        totalVolume -= price;

        totalListings--;
        totalSold++;

        // Emit an event for the NFT sale
        emit NFTSold(
            _listingId,
            msg.sender,
            listings[_listingId].tokenAddress,
            listings[_listingId].tokenId,
            price
        );

        // remove listing
        delete listings[_listingId];
    }

    // Function for the owner to update the marketplace fee
    function updateFee(uint256 _newFeeBasisPoints) external onlyOwner {
        feeBasisPoints = _newFeeBasisPoints;
        // Emit an event for the fee update
        emit FeeUpdated(_newFeeBasisPoints);
    }

    // Function for the owner to withdraw accumulated fees
    function withdrawFees() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        // Transfer the balance to the owner
        paymentToken.safeTransfer(msg.sender, balance);
    }

    // Function to get marketplace statistics such as total volume, average price, and total listings (live)
    function getMarketplaceStatisticsLive() external view returns (MarketStatistics memory data) {
        // Calculate average price if there are sold listings
        uint256 averagePrice = totalListings > 0 ? totalVolume / totalListings : 0;

        return data = MarketStatistics(
            totalVolume,
            averagePrice,
            totalListings
        );
    }

    // Function to get marketplace statistics such as total volume sold, average price, and total listings (sold)
    function getMarketplaceStatisticsSold() external view returns (MarketStatistics memory data) {
        uint256 averagePrice = totalSold > 0 ? totalVolumeSold / totalSold : 0;

        return data = MarketStatistics(
            totalVolumeSold,
            averagePrice,
            totalSold
        );
    }

    // Function to get all active listings for a specific NFT contract
    function getListingsByContract(address _tokenAddress) external view returns (Listing[] memory) {
        uint256 index;

        Listing[] memory Listings = new Listing[](totalListings);

        unchecked {
            for (uint256 i; i < totalListings; i++) {
                if (listings[i].tokenAddress == _tokenAddress) {
                    Listings[index] = listings[i];
                    index++;
                }
            }
        }
        return Listings;
    }

    function getListingsBySeller(address _seller) external view returns (Listing[] memory) {
        uint256 index;

        Listing[] memory sellerListings = new Listing[](totalListings);

        unchecked {
            for (uint256 i; i < totalListings; i++) {
                if (listings[i].seller == _seller) {
                    sellerListings[index] = listings[i];
                    index++;
                }
            }
        }
        return sellerListings;
    }
}