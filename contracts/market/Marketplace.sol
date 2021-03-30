// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./MarketplaceStorage.sol";
import "../library/Ownable.sol";
import "../library/Pausable.sol";
import "../library/IERC20.sol";

contract Marketplace is Ownable, Pausable, MarketplaceStorage {
    using SafeMath for uint256;
    using Address for address;

    /**
    * @dev Initialize this contract. Acts as a constructor
    * @param _acceptedToken - Address of the ERC20 accepted for this marketplace
    * @param _ownerCutPerMillion - owner cut per million
    * @param _owner - owner of the contract
    */
    constructor(
        address _acceptedToken,
        uint256 _ownerCutPerMillion,
        address _owner
    ) {
        // Fee init
        ownerCutPerMillion = _ownerCutPerMillion;

        require(_owner != address(0), "Invalid owner");
        transferOwnership(_owner);

        require(
            _acceptedToken.isContract(),
            "The accepted token address must be a deployed contract"
        );
        acceptedToken = ERC20Interface(_acceptedToken);
    }

    address public bitibots;

    // Set bitibots
    function setBitibots(address _bitibots) public onlyOwner {
        bitibots = _bitibots;
    }

    function isBitibotsContract(address _addr) private view returns (bool) {
        return address(bitibots) != address(0) && address(bitibots) == _addr;
    }

    /**
     * @dev Queries the existance of an order
     * @param nftAddress - Non fungible registry address
     * @param assetId - ID of the published NFT
     */
    function hasOrder(address nftAddress, uint256 assetId) view public returns (bool) {
        Order memory order = orderByAssetId[nftAddress][assetId];
        return order.id != 0;
    }

    /**
     * @dev Creates a new order
     * @param nftAddress - Non fungible registry address
     * @param assetId - ID of the published NFT
     * @param priceInWei - Price in Wei for the supported coin
     * @param expiresAt - Duration of the order (in hours)
     */
    function createOrder(
        address nftAddress,
        uint256 assetId,
        uint256 priceInWei,
        uint256 expiresAt
    ) public whenNotPaused {
        _createOrder(nftAddress, assetId, priceInWei, expiresAt);
    }

    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param nftAddress - Address of the NFT
     * @param assetId - ID of the published NFT
     */
    function cancelOrder(address nftAddress, uint256 assetId)
        public
        whenNotPaused
    {
        _cancelOrder(nftAddress, assetId);
    }

    /**
     * @dev Executes the sale for a published NFT
     * @param nftAddress - Address of the NFT
     * @param assetId - ID of the published NFT
     * @param price - Order price
     */
    function executeOrder(
        address nftAddress,
        uint256 assetId,
        uint256 price
    ) public whenNotPaused {
        _executeOrder(nftAddress, assetId, price);
    }

    /**
     * @dev Creates a new order
     * @param nftAddress - Non fungible registry address
     * @param assetId - ID of the published NFT
     * @param priceInWei - Price in Wei for the supported coin
     * @param expiresAt - Duration of the order (in hours)
     */
    function _createOrder(
        address nftAddress,
        uint256 assetId,
        uint256 priceInWei,
        uint256 expiresAt
    ) internal _requireAddressIsContract(nftAddress) {
        address sender = _msgSender();

        ERC721Interface erc721Token = ERC721Interface(nftAddress);
        address assetOwner = erc721Token.ownerOf(assetId);

        require(sender == assetOwner, "Only the owner can create orders");
        require(
            erc721Token.getApproved(assetId) == address(this) ||
                erc721Token.isApprovedForAll(assetOwner, address(this)),
            "The contract is not authorized to manage the asset"
        );
        require(priceInWei > 0, "Price should be bigger than 0");
        require(
            expiresAt > block.timestamp.add(1 minutes),
            "Publication should be more than 1 minute in the future"
        );

        bytes32 orderId =
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    assetOwner,
                    assetId,
                    nftAddress,
                    priceInWei
                )
            );

        // properly emit cancellation events
        if (hasOrder(nftAddress, assetId)) {
            Order memory prevOrder = orderByAssetId[nftAddress][assetId];
            emit OrderCancelled(prevOrder.id, assetId, prevOrder.seller, prevOrder.nftAddress);
        }

        orderByAssetId[nftAddress][assetId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: nftAddress,
            price: priceInWei,
            expiresAt: expiresAt
        });

        emit OrderCreated(
            orderId,
            assetId,
            assetOwner,
            nftAddress,
            priceInWei,
            expiresAt
        );
    }

    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param nftAddress - Address of the NFT
     * @param assetId - ID of the published NFT
     */
    function _cancelOrder(address nftAddress, uint256 assetId)
        internal
        _requireAddressIsContract(nftAddress)
        returns (Order memory)
    {
        address sender = _msgSender();
        Order memory order = orderByAssetId[nftAddress][assetId];

        require(order.id != 0, "Asset not published");
        require(
            order.seller == sender || sender == owner() || isBitibotsContract(sender),
            "Unauthorized user"
        );

        bytes32 orderId = order.id;
        address orderSeller = order.seller;
        address orderNftAddress = order.nftAddress;
        delete orderByAssetId[nftAddress][assetId];

        emit OrderCancelled(orderId, assetId, orderSeller, orderNftAddress);

        return order;
    }

    /**
     * @dev Executes the sale for a published NFT
     * @param nftAddress - Address of the NFT
     * @param assetId - ID of the published NFT
     * @param price - Order price
     */
    function _executeOrder(
        address nftAddress,
        uint256 assetId,
        uint256 price
    ) internal _requireAddressIsContract(nftAddress) returns (Order memory) {
        address sender = _msgSender();

        ERC721Interface erc721Token = ERC721Interface(nftAddress);

        Order memory order = orderByAssetId[nftAddress][assetId];

        require(order.id != 0, "Asset not published");

        address seller = order.seller;

        require(seller != address(0), "Invalid address");
        require(seller != sender, "Unauthorized user");
        require(order.price == price, "The price is not correct");
        require(block.timestamp < order.expiresAt, "The order expired");
        require(
            seller == erc721Token.ownerOf(assetId),
            "The seller is no longer the owner"
        );

        uint256 saleShareAmount = 0;

        bytes32 orderId = order.id;
        delete orderByAssetId[nftAddress][assetId];

        if (ownerCutPerMillion > 0) {
            // Calculate sale share
            saleShareAmount = price.mul(ownerCutPerMillion).div(1000000);

            // Transfer share amount for marketplace Owner
            require(
                acceptedToken.transferFrom(sender, owner(), saleShareAmount),
                "Transfering the cut to the Marketplace owner failed"
            );
        }

        // Transfer sale amount to seller
        require(
            acceptedToken.transferFrom(
                sender,
                seller,
                price.sub(saleShareAmount)
            ),
            "Transfering the sale amount to the seller failed"
        );

        // Transfer asset owner
        erc721Token.safeTransferFrom(seller, sender, assetId);

        emit OrderSuccessful(
            orderId,
            assetId,
            seller,
            nftAddress,
            price,
            sender
        );

        return order;
    }

    modifier _requireAddressIsContract(address addr) {
        require(addr.isContract(), "The NFT Address should be a contract");
        _;
    }
}
