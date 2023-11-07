// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing OpenZeppelin's ERC721 and ERC20 interfaces, ReentrancyGuard, and Ownable contracts
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// NFTMarketplace contract allows listing, buying, and selling of NFTs
contract NFTMarketplace is ReentrancyGuard, Ownable {
    // Structure for listing an NFT
    struct Listing {
        address seller;
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    // ERC20 token used for payments
    IERC20 public paymentToken;
    // Array to store all listings
    Listing[] public listings;

    // Marketplace fee in basis points (1% default)
    uint256 public feeBasisPoints = 100;

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
        // Transfer the NFT to the contract for escrow
        IERC721(_tokenAddress).transferFrom(msg.sender, address(this), _tokenId);
        // Add the new listing to the array
        listings.push(Listing({
            seller: msg.sender,
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            price: _price,
            active: true
        }));
        // Emit an event for the new listing
        emit ListingCreated(
            listings.length - 1,
            msg.sender,
            _tokenAddress,
            _tokenId,
            _price
        );
    }

    // Function to update the price of an existing listing
    function updateListing(uint256 _listingId, uint256 _newPrice) external nonReentrant {
        Listing storage listing = listings[_listingId];
        // Ensure that only the seller can update the listing
        require(msg.sender == listing.seller, "Only seller can update listing.");
        // Ensure the listing is active
        require(listing.active, "Listing is not active.");
        // Update the listing price
        listing.price = _newPrice;
        // Emit an event for the listing update
        emit ListingUpdated(_listingId, _newPrice);
    }

    // Function to remove an existing listing
    function removeListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        // Ensure that only the seller can remove the listing
        require(msg.sender == listing.seller, "Only seller can remove listing.");
        // Ensure the listing is active
        require(listing.active, "Listing is not active.");
        // Transfer the NFT back to the seller
        IERC721(listing.tokenAddress).transferFrom(address(this), listing.seller, listing.tokenId);
        // Set the listing as inactive
        listing.active = false;
        // Emit an event for the listing removal
        emit ListingRemoved(_listingId);
    }

    // Function to buy an NFT from an active listing
    function buyNFT(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        // Ensure the listing is active
        require(listing.active, "Listing is not active.");
        // Calculate the fee and the amount going to the seller
        uint256 fee = (listing.price * feeBasisPoints) / 10000;
        uint256 sellerAmount = listing.price - fee;
        // Transfer the fee to the marketplace
        require(paymentToken.transferFrom(msg.sender, address(this), fee), "Fee transfer failed.");
        // Transfer the payment to the seller
        require(paymentToken.transferFrom(msg.sender, listing.seller, sellerAmount), "Payment to seller failed.");
        // Transfer the NFT to the buyer
        IERC721(listing.tokenAddress).transferFrom(address(this), msg.sender, listing.tokenId);
        // Set the listing as inactive
        listing.active = false;
        // Emit an event for the NFT sale
        emit NFTSold(
            _listingId,
            msg.sender,
            listing.tokenAddress,
            listing.tokenId,
            listing.price
        );
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
        require(paymentToken.transfer(msg.sender, balance), "Withdrawal failed.");
    }

    // Function to get all active listings for a specific NFT contract
    function getActiveListingsByContract(address _tokenAddress) public view returns (Listing[] memory) {
        // Count active listings for the contract
        uint256 activeCount = 0;
        for (uint256 i = 0; i < listings.length; i++) {
            if (listings[i].active && listings[i].tokenAddress == _tokenAddress) {
                activeCount++;
            }
        }

        // Create an array to hold the active listings
        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 currentIndex = 0;
        // Populate the array with active listings
        for (uint256 i = 0; i < listings.length; i++) {
            if (listings[i].active && listings[i].tokenAddress == _tokenAddress) {
                activeListings[currentIndex] = listings[i];
                currentIndex++;
            }
        }
        return activeListings;
    }

    // Function to get marketplace statistics such as total volume, average price, and total listings
    function getMarketplaceStatistics() public view returns (uint256 totalVolume, uint256 averagePrice, uint256 totalListings) {
        uint256 totalPrice = 0;
        uint256 totalSold = 0;
        // Loop through all listings to calculate statistics
        for (uint256 i = 0; i < listings.length; i++) {
            if (!listings[i].active) { // Assuming a listing is inactive once sold
                totalSold++;
                totalPrice += listings[i].price;
            }
        }
        // Calculate average price if there are sold listings
        averagePrice = totalSold > 0 ? totalPrice / totalSold : 0;
        // Total listings is the length of the listings array
        totalListings = listings.length;
        // Total volume is the sum of all sold listing prices
        totalVolume = totalPrice;
        return (totalVolume, averagePrice, totalListings);
    }

    // Function to get all active listings by a specific seller
    function getActiveListingsBySeller(address _seller) public view returns (Listing[] memory) {
        // Count active listings for the seller
        uint256 activeCount = 0;
        for (uint256 i = 0; i < listings.length; i++) {
            if (listings[i].active && listings[i].seller == _seller) {
                activeCount++;
            }
        }

        // Create an array to hold the seller's active listings
        Listing[] memory sellerListings = new Listing[](activeCount);
        uint256 currentIndex = 0;
        // Populate the array with the seller's active listings
        for (uint256 i = 0; i < listings.length; i++) {
            if (listings[i].active && listings[i].seller == _seller) {
                sellerListings[currentIndex] = listings[i];
                currentIndex++;
            }
        }
        return sellerListings;
    }
}
