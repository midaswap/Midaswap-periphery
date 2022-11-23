// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './FractionNFT.sol';
import './MidasERC721Vault.sol';
import './CustodyPositionManager.sol';


contract MidaswapRouter {
    
    function swapForSingleNFT721(ExactOutputSingleParams calldata params, address targetAsset, uint256 tokenId) 
        external 
        payable 
        returns (uint256 amountIn) 
    {
        params.tokenA = FractionNFT.getVtokenAddress721(targetAsset);
        amountIn = ISwapRouter.exactOutputSingle(params);
        MidasERC721Vault.withdrawSingleNFT(tokenId, msg.sender);
    }

    function swapFromSingleNFT721(ExactInputSingleParams calldata params, address fromAsset, uint256 tokenId)
        external
        payable
        returns (uint256 amountOut)
    {
        params.tokenA = FractionNFT.getVtokenAddress721(fromAsset);
        amountOut = ISwapRouter.exactOutputSingle(params);
        MidasERC721Vault.depositSingleNFT(tokenId, params.sqrtPriceLimitX96);
    }

    function swapForMultiNFT721(){}

    function swapForSingleNFT1155(ExactOutputSingleParams calldata params, address targetAsset, uint256 id, uint256 tokenId) 
        external 
        payable 
        returns (uint256 amountIn) 
    {
        params.tokenA = FractionNFT.getVtokenAddress1155(targetAsset, id);
        amountIn = ISwapRouter.exactOutputSingle(params);

    }




    function superSwapForSingleNFT(){}


    function superSwapForMultiNFTs(){}




}