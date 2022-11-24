// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;
pragma abicoder v2;

import './MidasVault.sol';

interface ICustodyPositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function getPositionInfo(uint256 tokenId) external view returns (int24 tickLower, int24 tickUpper);

    function getPoolInfo(uint256 tokenId) external view returns (address pool);

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 poolFee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mintNewPosition(address provider, MintParams memory params) external returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function decreaseLiquidityInRatio(
        uint256 tokenId, 
        uint128 ratio
    ) 
        external 
        returns (
            uint256 amount0, 
            uint256 amount1
        );

    function decreaseLiquidity(
        uint256 tokenId, 
        uint128 subLiquidity
    ) 
        external 
        returns (
            uint128 remainLiquidity,
            uint256 amount0, 
            uint256 amount1
        );

    function burn(uint256 tokenId) external returns (bool);
    
}

contract MidaswapRouter {
    
    address private custodyPositionManager;
    MidasVault public midasVault;
        
    constructor (address _custodyPositionManager, address _midasVault) public {
        custodyPositionManager = _custodyPositionManager;
        midasVault = MidasVault(_midasVault);
    }

    /* ========== SWAPS OPERATIONS ========== */

    // function swapFromERC721()
    // function swapFromERC1155()
    // function swapFromFractions()
    // function swapToERC721()
    // function swapToERC1155()

    /* ========== LIQUIDITY MANAGEMENT ========== */
    
    function createAndInitializePoolIfNecessary(
        address nftAddress, 
        address ftAddress, 
        uint256 id, 
        uint24 poolFee,
        uint160 sqrtPriceX96
        ) external returns (address poolAddress) 
    {
        // Transfer NFT into fractions 
        address token0 = midasVault.create(nftAddress, id);
        // Get the FT address
        address token1 = ftAddress;
        // Create a liquidity Pool of Fractions & FT if necessary
        poolAddress = ICustodyPositionManager(custodyPositionManager)
                    .createAndInitializePoolIfNecessary(
                        token0, 
                        token1, 
                        poolFee, 
                        sqrtPriceX96);
    }
        
    function mintFromNFTs(
        address nftAddress, 
        address ftAddress,
        address poolAddress,
        uint256[] memory tokenId, 
        uint256 id,
        uint256 amount,
        ICustodyPositionManager.MintParams memory params
        ) external returns (
            uint256 lpTokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1) 
    {
        if(id > 0){
            midasVault.exchangeFromERC1155(nftAddress, id, amount);
            params.token0 = midasVault.getVtokenAddress1155(nftAddress, id);
            params.token1 = ftAddress;
            (lpTokenId, liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).mintNewPosition(msg.sender, params);  
        } else {
            midasVault.exchangeERC721FromLP(msg.sender, nftAddress, tokenId, poolAddress, params.tickLower, params.tickUpper);
            params.token0 = midasVault.getVtokenAddress721(nftAddress);
            params.token1 = ftAddress;
            (lpTokenId, liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).mintNewPosition(msg.sender, params);          
        }
    }

    /// This function only support for mint a new liquidity position from ERC721 fractions.
    function mintFromERC721Fractions(
        address fractionAddress, 
        address ftAddress,
        ICustodyPositionManager.MintParams memory params
        ) external returns (
            uint256 lpTokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1) 
    {
        params.token0 = fractionAddress;
        params.token1 = ftAddress;
        (lpTokenId, liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).mintNewPosition(msg.sender, params);  
    }

    function increaseLiquidityFromNFTs(
        address nftAddress,
        uint256 lpTokenId,
        uint256[] calldata tokenId, 
        uint256 id,
        uint256 amountAdd0,
        uint256 amountAdd1
        ) external returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if(id > 0){
            midasVault.exchangeFromERC1155(nftAddress, id, amountAdd0);
            (liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).increaseLiquidityCurrentRange(lpTokenId, amountAdd0, amountAdd1);  
        } else {
            (int24 tickLower, int24 tickUpper) = ICustodyPositionManager(custodyPositionManager).getPositionInfo(lpTokenId);
            address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolInfo(lpTokenId);           
            midasVault.exchangeERC721FromLP(msg.sender, nftAddress, tokenId, poolAddress, tickLower, tickUpper);
            (liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).increaseLiquidityCurrentRange(lpTokenId, amountAdd0, amountAdd1);          
        }
    }

    function increaseLiquidityFromFractions(
        uint256 amountAdd0,
        uint256 amountAdd1,
        uint256 lpTokenId
    ) external returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1        
    )
    {
        (liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).increaseLiquidityCurrentRange(lpTokenId, amountAdd0, amountAdd1);
    }

    function decreaseLiquidity(
        address nftAddress,
        uint256 lpTokenId,
        uint128 subLiquidity,
        uint256[] calldata tokenId
    ) external returns (
        uint128 remainLiquidity,
        uint256 amount0, 
        uint256 amount1
    )
    {
        if (tokenId.length == 0) {
            (remainLiquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).decreaseLiquidity(lpTokenId, subLiquidity);
        } else {
            (remainLiquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).decreaseLiquidity(lpTokenId, subLiquidity);
            require(tokenId.length < amount0, 'Over the assets you own!');
            address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolInfo(lpTokenId);
            midasVault.withdrawERC721(nftAddress, poolAddress, tokenId, msg.sender);
        }
    }

    function burn(uint256 lpTokenId) external {
        require(ICustodyPositionManager(custodyPositionManager).burn(lpTokenId), 'Burn LP token failed!');
    }

}
