// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import './interfaces/IRoyaltyEngineV1.sol';
import './MidasVault.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './interfaces/ISwapRouter.sol';

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

    function getPoolAddress(address token0, address token1) external view returns (address pool);

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

    function updateLiquidity(uint256 tokenId, uint256 nftAmount)  
        external
        returns (
            uint128 liquidity,
            uint256 amount0, 
            uint256 amount1
        );

    function burn(uint256 tokenId) external returns (bool);

}

contract MidaswapRouterWithRoyalties {

    ISwapRouter public immutable swapRouter;
    IRoyaltyEngineV1 public royaltyEngine;
    MidasVault public midasVault;
    address private custodyPositionManager;
    uint256 public constant feeRate = 1e17;
        
    constructor (address _custodyPositionManager, address _midasVault, ISwapRouter _swapRouter, address _royaltyEngine) {
        custodyPositionManager = _custodyPositionManager;
        midasVault = MidasVault(_midasVault);
        swapRouter = _swapRouter;
        royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
    }

    /* ========== TRADING OPERATIONS ========== */

    function buyERC721(
        uint256[] calldata tokenId,
        uint256 amountInMaximum,
        address nftAddress,
        address ftAddress,
        uint24 poolFee
    ) external returns (uint256 amountIn) {
        address token1 = midasVault.getVtokenAddress721(nftAddress);
        uint256 amountOut = tokenId.length;
        amountIn = _swapExactOutputERC721Single(amountOut, amountInMaximum, tokenId[0], nftAddress, ftAddress, token1, poolFee);
        address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolAddress(token1, ftAddress); 
        midasVault.withdrawFromFTtoERC721(nftAddress, poolAddress, tokenId, msg.sender);
    }

    // This function is meant to trade NFTs outside the current tick
    function buyERC721Conduit(
        uint256[] calldata tokenId,
        uint256 amountInMaximum,
        address nftAddress,
        address ftAddress
    ) external returns (uint256 amountIn) {
        // Check if these tokenIds outside of current tick
        address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolAddress(nftAddress, ftAddress); 
        require(midasVault.checkTickPriceOutside(poolAddress, tokenId), 'Cannot be traded through this conduit!');

        // Transfer the specific amount of ft token to this address
        TransferHelper.safeTransferFrom(ftAddress, msg.sender, address(this), amountInMaximum);
        TransferHelper.safeApprove(ftAddress, address(this), amountInMaximum);

        // Initial the amountIn
        amountIn = 0;
        // Help LPs decrease the liquidity   
        for (uint i = 0; i < tokenId.length; i++){
            uint256 lpTokenId = nftPositionMap[poolAddress][tokenId[i]];
            address owner = midasVault.getOwner(tokenId[i], poolAddress);
            uint256 value = _getPrice(lpTokenId);
            TransferHelper.safeTransferFrom(ftAddress, address(this), owner, value);  // Here decimal needs to be checked
            amountIn += value;
            ICustodyPositionManager(custodyPositionManager).updateLiquidity(lpTokenId, 1);
        }

        uint256 totalRoyalties = _sendRoyalties(nftAddress, ftAddress, tokenId[0], amountIn, msg.sender);
        // Transfer NFTs to trader
        midasVault.withdrawFromFTtoERC721Conduit(nftAddress, poolAddress, tokenId, msg.sender);

        if (amountIn + totalRoyalties < amountInMaximum) {
            TransferHelper.safeApprove(ftAddress, address(swapRouter), 0);
            TransferHelper.safeTransfer(ftAddress, msg.sender, amountInMaximum - amountIn - totalRoyalties);
        }
    }

    function buyERC1155(
        address nftAddress,
        uint256[] calldata amountInMaximum,
        address[] calldata ftAddress,
        uint256[] calldata id,
        uint256[] calldata amountOut,
        uint24[] calldata poolFee
    ) external returns (uint256[] memory amountIn) {
        require(id.length == amountInMaximum.length && ftAddress.length == amountOut.length, 'Inputs not match!');
        require(id.length == ftAddress.length && amountInMaximum.length == poolFee.length, 'Inputs not match!');
        for (uint i = 0; i < id.length; i++) {
            address token1 =  midasVault.getVtokenAddress1155(nftAddress, id[i]);
            amountIn[i] = _swapExactOutputSingle(amountOut[i], amountInMaximum[i], ftAddress[i], token1, poolFee[i]);
            midasVault.exchangeToERC1155(nftAddress, id[i], amountOut[i], msg.sender);
        }
    }

    function sellERC721(
        uint256[] calldata tokenId,
        address nftAddress,
        address ftAddress,
        uint24 poolFee
    ) external returns (uint256 amountOut) {
        uint256 amountIn = tokenId.length;
        address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolAddress(midasVault.getVtokenAddress721(nftAddress), ftAddress);
        midasVault.exchangeERC721FromTrader(msg.sender, nftAddress, poolAddress, tokenId);
        amountOut = _swapExactInputSingle(amountIn, midasVault.getVtokenAddress721(nftAddress), ftAddress, poolFee);
        _sendRoyalties(nftAddress, ftAddress, tokenId[0], amountOut, msg.sender);
    }

    function sellERC1155(
        uint256[] calldata id,
        address nftAddress,
        address[] calldata ftAddress,
        uint24[] calldata poolFee,
        uint256[] calldata amountIn
    ) external returns (uint256[] memory amountOut) {
        require(id.length == ftAddress.length && amountIn.length == poolFee.length, 'Inputs not match!');
        require(id.length == amountIn.length, 'Inputs not match!');        
        for (uint i = 0; i < id.length; i++) {
            midasVault.exchangeFromERC1155(nftAddress, id[i], amountIn[i], msg.sender);
            amountOut[i] = _swapExactInputSingle(amountIn[i], midasVault.getVtokenAddress1155(nftAddress, id[i]), ftAddress[i], poolFee[i]);
        }
    }

    function _sendRoyalties(
        address nftAddress,
        address ftAddress,
        uint256 tokenId,
        uint256 salesPrice,
        address sender
        ) internal returns (uint256 totalRoyalties) {
            (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyaltyView(nftAddress, tokenId, salesPrice);
            for (uint i = 0; i < amounts.length; i++) {
                totalRoyalties += amounts[i];
            }
            TransferHelper.safeTransferFrom(ftAddress, sender, address(this), totalRoyalties);
            TransferHelper.safeApprove(ftAddress, address(this), totalRoyalties);
            TransferHelper.safeTransferFrom(ftAddress, address(this), address(midasVault), totalRoyalties * feeRate / 1e18);
            for (uint i = 0; i < recipients.length; i++) {
                TransferHelper.safeTransferFrom(ftAddress, address(this), recipients[i], amounts[i] * (1 - feeRate / 1e18));
            }
        }

    function _swapExactOutputERC721Single(
        uint256 amountOut, 
        uint256 amountInMaximum,
        uint256 tokenId,
        address nftAddress,
        address token0,
        address token1,
        uint24 poolFee
        ) internal returns (uint256 amountIn) {
        // Transfer the specified amount of token0 to this contract.
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend the specified `amountInMaximum` of token0.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to achieve a better swap.
        TransferHelper.safeApprove(token0, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);
        uint256 totalRoyalties = _sendRoyalties(nftAddress, token0, tokenId, amountIn, msg.sender);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn + totalRoyalties < amountInMaximum) {
            TransferHelper.safeApprove(token0, address(swapRouter), 0);
            TransferHelper.safeTransfer(token0, msg.sender, amountInMaximum - amountIn - totalRoyalties);
        }
    }    

    function _swapExactOutputSingle(
        uint256 amountOut, 
        uint256 amountInMaximum,
        address token0,
        address token1,
        uint24 poolFee
        ) internal returns (uint256 amountIn) {
        // Transfer the specified amount of token0 to this contract.
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend the specified `amountInMaximum` of token0.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to achieve a better swap.
        TransferHelper.safeApprove(token0, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(token0, address(swapRouter), 0);
            TransferHelper.safeTransfer(token0, msg.sender, amountInMaximum - amountIn);
        }
    }    


    function _swapExactInputSingle(
        uint256 amountIn,
        address token0,
        address token1,
        uint24 poolFee
        ) internal returns (uint256 amountOut) {
        // msg.sender must approve this contract

        // Transfer the specified amount of token0 to this contract.
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountIn);

        // Approve the router to spend token0.
        TransferHelper.safeApprove(token0, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    function _getPrice(uint256 lpTokenId) internal view returns (uint256 value) {
        (int24 tickLower, int24 tickUpper) = ICustodyPositionManager(custodyPositionManager).getPositionInfo(lpTokenId);
        uint256 sqrtRatioX96A = TickMath.getSqrtRatioAtTick(tickLower);
        uint256 sqrtRatioX96B = TickMath.getSqrtRatioAtTick(tickUpper);
        value = (TickMath.getPrice(sqrtRatioX96A) + TickMath.getPrice(sqrtRatioX96B)) / 2;
    }

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

    mapping(address => mapping(uint256 => uint256)) nftPositionMap; 

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
            midasVault.exchangeFromERC1155(nftAddress, id, amount, msg.sender);
            params.token0 = midasVault.getVtokenAddress1155(nftAddress, id);
            params.token1 = ftAddress;
            (lpTokenId, liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).mintNewPosition(msg.sender, params);  
        } else {
            midasVault.exchangeERC721FromLP(msg.sender, nftAddress, tokenId, poolAddress, params.tickLower, params.tickUpper);
            params.token0 = midasVault.getVtokenAddress721(nftAddress);
            params.token1 = ftAddress;
            (lpTokenId, liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).mintNewPosition(msg.sender, params); 
            for(uint i = 0; i < tokenId.length; i++){
                nftPositionMap[poolAddress][tokenId[i]] = lpTokenId;
            }
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
            midasVault.exchangeFromERC1155(nftAddress, id, amountAdd0, msg.sender);
            (liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).increaseLiquidityCurrentRange(lpTokenId, amountAdd0, amountAdd1);  
        } else {
            (int24 tickLower, int24 tickUpper) = ICustodyPositionManager(custodyPositionManager).getPositionInfo(lpTokenId);
            address poolAddress = ICustodyPositionManager(custodyPositionManager).getPoolInfo(lpTokenId);           
            midasVault.exchangeERC721FromLP(msg.sender, nftAddress, tokenId, poolAddress, tickLower, tickUpper);
            (liquidity, amount0, amount1) = ICustodyPositionManager(custodyPositionManager).increaseLiquidityCurrentRange(lpTokenId, amountAdd0, amountAdd1);
            for(uint i = 0; i < tokenId.length; i++){
                nftPositionMap[poolAddress][tokenId[i]] = lpTokenId;
            }          
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
            midasVault.withdrawERC721FromLP(nftAddress, poolAddress, tokenId, msg.sender);
            for(uint i = 0; i < tokenId.length; i++){
                delete nftPositionMap[poolAddress][tokenId[i]];
            }
        }
    }

    function burn(uint256 lpTokenId) external {
        require(ICustodyPositionManager(custodyPositionManager).burn(lpTokenId), 'Burn LP token failed!');
    }

}
