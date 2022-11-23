// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1/contracts/token/ERC721/IERC721Receiver.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1/contracts/token/ERC721/ERC721.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.1/contracts/access/Ownable.sol';
import 'https://github.com/Uniswap/v3-core/contracts/libraries/TickMath.sol';
import './libraries/TransferHelper.sol';
import './interfaces/INonfungiblePositionManager.sol';


contract CustodyPositionManager is Ownable, ERC721, IERC721Receiver {

    int24 private constant MIN_TICK = -24850;
    int24 private constant MAX_TICK = -20800;

    event PoolCreated(address pool);
    event NewPositionMinted(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    
    /// @dev Set the NonfungiblePositionManager address 
    INonfungiblePositionManager public nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    constructor() ERC721("MidasCustodyLPToken", "MCLPT") {}

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
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

    /// @dev Implementing create and initialize the Pool 
    /// @param token0        The address of token0
    /// @param token1        The address of token1
    /// @param poolFee       The fee amount of the v3 pool for the specified token pair
    /// @param sqrtPriceX96  The initial square root price of the pool as a Q64.96 value
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 poolFee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool) {
        pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, poolFee, sqrtPriceX96);
        emit PoolCreated(pool);
    }

    function mintNewPosition(INonfungiblePositionManager.MintParams memory params) external returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ){
        // transfer tokens to contract
        TransferHelper.safeTransferFrom(params.token0, msg.sender, address(this), params.amount0Desired);
        TransferHelper.safeTransferFrom(params.token1, msg.sender, address(this), params.amount1Desired);
        // Approve the position manager
        TransferHelper.safeApprove(params.token0, address(nonfungiblePositionManager), params.amount0Desired);
        TransferHelper.safeApprove(params.token1, address(nonfungiblePositionManager), params.amount1Desired);
        // The values for tickLower and tickUpper may not work for all tick spacings.
        // Setting amount0Min and amount1Min to 0 is unsafe.
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
        // Create a deposit record
        deposits[tokenId] = Deposit({owner: msg.sender, liquidity: liquidity, token0: params.token0, token1: params.token1});
        // Mint a custody token
        _mint(msg.sender, tokenId);
        // Remove allowance and refund in both assets.
        emit NewPositionMinted(tokenId, liquidity, amount0, amount1);
        if (amount0 < params.amount0Desired) {
            TransferHelper.safeApprove(params.token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = params.amount0Desired - amount0;
            TransferHelper.safeTransfer(params.token0, msg.sender, refund0);
        }

        if (amount1 < params.amount1Desired) {
            TransferHelper.safeApprove(params.token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 =  params.amount1Desired - amount1;
            TransferHelper.safeTransfer(params.token1, msg.sender, refund1);
        }
    }


    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
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
        )
    {
        TransferHelper.safeTransferFrom(deposits[tokenId].token0, msg.sender, address(this), amountAdd0);
        TransferHelper.safeTransferFrom(deposits[tokenId].token1, msg.sender, address(this), amountAdd1);

        TransferHelper.safeApprove(deposits[tokenId].token0, address(nonfungiblePositionManager), amountAdd0);
        TransferHelper.safeApprove(deposits[tokenId].token1, address(nonfungiblePositionManager), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit
        // set amount0Max and amount1Max to type(uint128).max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // send collected fees back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice A function that decreases the current liquidity by a specific ratio.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidityInRatio(
        uint256 tokenId, 
        uint128 ratio
    ) 
        external 
        returns (
            uint256 amount0, 
            uint256 amount1
        ) 
    {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;
        require(ratio < 1, "Cannot decrease liquidity more than you have!");
        uint128 subLiquidity = liquidity * ratio;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: subLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice A function that decreases all the current liquidity.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseAllLiquidity(uint256 tokenId) 
        external 
        returns (
            uint256 amount0, 
            uint256 amount1
        ) 
    {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);

    }
    
    /// @dev            A function that withdraws the liquidity to LPs regarding the NFT which is traded outside of current tick price
    /// @notice         Here will not transfer the assets back to LP, as they have gotten the assets directly.
    ///                 Custody contract will keep this part of liquidity.
    /// @param tokenId  The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseSpecificLiquidity(uint256 tokenId, uint128 subLiquidity) 
        onlyOwner 
        external
        returns (
            uint256 amount0, 
            uint256 amount1
        ) 
    {
        require(subLiquidity < deposits[tokenId].liquidity, "Over withdrawal!");
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: subLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721
    function retrieveNFT(uint256 tokenId) external {
        // must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // remove information related to tokenId
        delete deposits[tokenId];
        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function burn(uint256 tokenId) external {
        // must be the owner of the NFT        
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // burn the custody token
        _burn(tokenId);    
        // remove information related to tokenId
        delete deposits[tokenId];
        // burn the Uni-LPtoken
        nonfungiblePositionManager.burn(tokenId);
    }
}
