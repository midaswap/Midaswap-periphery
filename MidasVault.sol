// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
// import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract MidasVault is IERC721Receiver {
    // The address of MidaswapRouter
    address public swapRouter;

    // @dev MIN_TICK & MAX_TICK refer to all the range, 
    //      which only used in deposited NFT assets from traders.
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    
    constructor (address _swapRouter) public {
        swapRouter = _swapRouter;
    }

    modifier onlyRouter() {
        require(msg.sender == swapRouter, "No Permission to withdraw!");
        _;
    }

    // Implementing `onERC721Received` so address(this) contract can receive the NFTs
    // Note that the operator is recorded as the owner of the NFTs 
    function onERC721Received(
        address operator, 
        address from, 
        uint tokenId, 
        bytes calldata
    ) external override returns (bytes4) 
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    /* ========== ERC721 ASSETS ========== */

    struct DepositParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
    }
    
    /// @dev poolAddress => tokenID => DepositParams
    mapping(address => mapping(uint256 => DepositParams)) public deposits;
   
    function depositSingleNFTFromLP(
        address nftAddress, 
        uint256 tokenId,        
        address poolAddress,
        int24 tickLower,
        int24 tickUpper
    ) external payable returns (bool) 
    {
        // Deposit the NFT into Vault
        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        // Create a deposit record
        deposits[poolAddress][tokenId] = DepositParams({owner: msg.sender, tickLower: tickLower, tickUpper: tickUpper});
        return true;
    }

    function depositSingleNFTFromTrader(
        address nftAddress,
        address poolAddress,
        uint256 tokenId
    ) external payable returns (bool) {
        // Deposit the NFT into Vault
        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        // Create a deposit record
        deposits[poolAddress][tokenId] = DepositParams({owner: address(this), tickLower: MIN_TICK, tickUpper: MAX_TICK});
        return true;
    }

    function depositNFTsFromLP(
        address nftAddress,
        uint256[] calldata tokenId,
        address poolAddress,
        int24 tickLower,
        int24 tickUpper
    ) external payable returns (bool) 
    {
        for (uint i = 0; i < tokenId.length; i++) {
            // Deposit the NFT into Vault
            IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId[i]);
            // Create a deposit record
            deposits[poolAddress][tokenId[i]] = DepositParams({owner: msg.sender, tickLower: tickLower, tickUpper: tickUpper});
        }
        return true;
    }

    function depositNFTsFromTrader(
        address nftAddress,
        uint256[] calldata tokenId,
        address poolAddress
    ) external payable returns (bool) 
    {
        for (uint i = 0; i < tokenId.length; i++) {
            // Deposit the NFT into Vault
            IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId[i]);
            // Create a deposit record
            deposits[poolAddress][tokenId[i]] = DepositParams({owner: address(this), tickLower: MIN_TICK, tickUpper: MAX_TICK});
        }
        return true;
    }

    function withdrawSingleNFT(
        address nftAddress,
        address poolAddress,
        uint256 tokenId,
        address receiver
    ) onlyRouter external returns (bool) {
        // Withdraw NFT from Vault
        IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenId);
        // Delete the deposit record
        delete deposits[poolAddress][tokenId];
        return true;
    }

    function withdrawNFTs(
        address nftAddress,
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
    ) onlyRouter external returns (bool) {
        for (uint i = 0; i < tokenId.length; i++) {
            // Withdraw the NFT from Vault
            IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenId[i]);
            // Delete the deposit record
            delete deposits[poolAddress][tokenId[i]];
        }
        return true;
    }

    /* ========== ERC1155 ASSETS ========== */
    
    // struct ERC1155AssetParams {
    //     address nftAddress;
    //     int id;
    //     uint256 amount;
    // }

    // // @dev poolAddress => AssetParams
    // mapping(address => ERC1155AssetParams) public assetInfo;
    
    // function depositERC1155(
    //     address nftAddress, 
    //     address poolAddress,
    //     uint256 id,
    //     uint256 amount
    // ) external payable returns (bool) {
    //     // Deposit ERC1155 into Vault
    //     IERC1155(nftAddress).safeTransferFrom(msg.sender, address(this), id, amount);
    //     // Update assets info
    //     uint256 amountUpdated = assetInfo[poolAddress].amount + amount;
    //     assetInfo[poolAddress] = ERC1155AssetParams({nftAddress: nftAddress, id: id, amount: amountUpdated});
        
    //     return true;
    // }

    // function depositBatchERC1155(
    //     address nftAddress,
    //     address[] calldata poolAddress,
    //     uint256[] calldata ids,
    //     uint256[] calldata amounts
    // ) external payable returns (bool) {
    //     // Check lengths match
    //     require(poolAddress.length == ids.length, "depositBatchERC1155: args length diff");
    //     require(ids.length == amounts.length, "depositBatchERC1155: args length diff");
        
    //     // Deposit ERC1155 into Vault
    //     IERC1155(nftAddress).safeBatchTransferFrom(msg.sender, address(this), ids, amounts);
        
    //     // Update assets info
    //     for (uint i = 0; i < ids.length; i++) {
    //         uint256 amountUpdated = assetInfo[poolAddress[i]].amount + amounts[i];
    //         assetInfo[poolAddress[i]] = ERC1155AssetParams({nftAddress: nftAddress, id: ids[i], amount: amountUpdated});            
    //     }
       
    //     return true;
    // }

    // function withdrawERC1155(
    //     address nftAddress,
    //     address poolAddress,
    //     uint256 id,
    //     uint256 amount,
    //     address receiver
    // ) onlyRouter external returns (bool) {
    //     // Check balance 
    //     require(assetInfo[poolAddress].amount > amount, 'Over withdraw!');
       
    //     // Withdraw NFT from Vault
    //     IERC1155(nftAddress).safeTransferFrom(address(this), receiver, id, amount);
        
    //     // Update assets info
    //     uint256 amountUpdated = assetInfo[poolAddress].amount - amount;
    //     assetInfo[poolAddress] = ERC1155AssetParams({nftAddress: nftAddress, id: id, amount: amountUpdated});
        
    //     return true;
    // }
}
