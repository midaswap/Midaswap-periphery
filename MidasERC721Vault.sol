// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;
pragma abicoder v2;

import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1/contracts/token/ERC721/IERC721Receiver.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1/contracts/token/ERC721/IERC721.sol';


contract MidasVault is IERC721Receiver{
        
    // Implementing `onERC721Received` so this contract can receive the NFTs
    // Note that the operator is recorded as the owner of the NFTs 
    function onERC721Received(
        address operator, 
        address from, 
        uint tokenId, 
        bytes calldata
    ) 
        external 
        override 
        returns (bytes4) 
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    struct depositParams {
        address nftAddress;
        address poolAddress;
        int24 tickLower;
        int24 tickUpper;
        address owner;    
    }

    /// @dev deposits[tokenId] => depositParams
    mapping(uint256 => depositParams) public deposits;
   
    function depositSingleNFTFromLP(uint256 tokenId, depositParams memory params) external payable returns (bool) {
        // Deposit the NFT into Vault
        IERC721(params.token0).safeTransferFrom(msg.sender, this(address), tokenId);
        // Create a deposit record
        params.owner = msg.sender;
        deposits[tokenId] = params; 
        return true;
    }

    function depositSingleNFTFromTrader(uint256 tokenId, depositParams memory params) external payable returns (bool) {
        // Deposit the NFT into Vault
        IERC721(params.token0).safeTransferFrom(msg.sender, this(address), tokenId);
        // Create a deposit record
        params.tickLower = -887272;
        params.tickUpper = 887272;
        params.owner = msg.sender;
        deposits[tokenId] = params; 
        return true;
    }

    function withdrawSingleNFT(uint256 tokenId, address receiver) external payable returns (bool) {
        // Withdraw the NFT from Vault
        IERC721(params.token0).safeTransferFrom(this(address), msg.sender, tokenId);
        delete deposits[tokenId];
        return true;
    }

}