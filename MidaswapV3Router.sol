// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./SwapPool.sol";
import "./FractionNFT.sol";


interface ICustodyPositionManager{
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

    function mintNewPosition(address sender,MintParams  memory params )   external;
}


/**
 this contract is create  pool  and  swap  addpool
 */

contract MidaswapV3Router {
    //nft-> tokenA->tokenB pools address
    mapping(address => mapping(address=> mapping(address=>address))) private  getPool721;
    //nft-> tokenA->tokenB id pools
    mapping(address => mapping(address=> mapping(address=> mapping(uint256=>address)))) private   getPool1155;
    
    address private fractionNFTAddress;

    address private custodyPositionManagerAddress;
    // storage   pool detail 
    PoolInfo[]  private poolInfoArray;

    // nft -> token b address => pools detial
    mapping(address => mapping(address=>PoolInfo)) private  poolMap721;
        // nft -> token b address=>1155 id  => pools detial
    mapping(address => mapping(address=> mapping(uint=>PoolInfo))) private  poolMap1155;
       // client addreess  ->  pools  all detial
    mapping(address =>PoolInfo[]) private myAddPoolArr;
       // client addreess  ->  pools  all detial
    mapping(address => mapping(address=> uint)) private myAddPoolMap;


    struct PoolInfo{
        address poolsAddress;
        address nft_address;
        uint id;
        address tokenA;
        address tokenB;
        address fractionNFTAddress;
    }

    constructor (address nftAddress, address tokenB,address managerAddress_)  {
        fractionNFTAddress= address(new  FractionNFT());
        createPool(nftAddress, 0, tokenB, 80 ether);
        custodyPositionManagerAddress=managerAddress_;
    }

    function  getPoolInfo(address nft_address,address tokenB,uint  id)public  view  returns (PoolInfo memory){
        if(id>0){
            return  poolMap1155[nft_address][tokenB][id];
        }else{
            return  poolMap721[nft_address][tokenB];
        }

    }

    function  getPoolInfoArray()public  view  returns (PoolInfo[] memory){
        return  poolInfoArray;
    }

    function getPoolAddress(address nft_address,address tokenB,uint  id ) public  view  returns(address) {
        if(id > 0){
            address vtokenAddress = FractionNFT(fractionNFTAddress).getVtokenAddress1155(nft_address,id);
            return    getPool1155[nft_address][vtokenAddress][tokenB][id];
        }else{
            address vtokenAddress = FractionNFT(fractionNFTAddress).getVtokenAddress721(nft_address);
            return   getPool721[nft_address][vtokenAddress][tokenB];
        }
    }

    function getVtoken(address nft_address,uint  id) public  view  returns(address) {
        if(id > 0){
            return  FractionNFT(fractionNFTAddress).getVtokenAddress1155(nft_address,id);
        }else{
            return  FractionNFT(fractionNFTAddress).getVtokenAddress721(nft_address);
        }
    }


    function getTokenOut(address pools,address toAddress, uint amountFrom)public view returns(uint){
        return  SwapPool(pools).getToken(toAddress,amountFrom);
    }


    function getLpToken(address pools, address owner)public view returns(uint, uint){
        return  SwapPool(pools).getLpToken(owner);
    }

    function getMyAddPoolArr(address owner)public view returns(PoolInfo[] memory){
        return  myAddPoolArr[owner];
    }

    function getFractionNFTAddress()public view returns(address){
        return fractionNFTAddress;
    }


    function swap(address pools,address toAddress ,uint _amount) public {
        SwapPool(pools).swap(msg.sender,toAddress,_amount);
    }

    function createPool(address nft_address,uint  id ,address tokenB ,uint scale) public {
        if(id > 0){
            address  vtokenAddress = FractionNFT(fractionNFTAddress).create(nft_address,id);
            address pools = getPool1155[nft_address][vtokenAddress][tokenB][id];
            if(pools == address(0)){
                pools= address(new  SwapPool(vtokenAddress,tokenB,address(this),scale));
                getPool1155[nft_address][vtokenAddress][tokenB][id]=pools;
                PoolInfo memory poolInfo= PoolInfo(pools,nft_address,id,vtokenAddress,tokenB,fractionNFTAddress);
                poolInfoArray.push(poolInfo);
                poolMap1155[nft_address][tokenB][id]= poolInfo;
            }
        }else{
            address  vtokenAddress =  FractionNFT(fractionNFTAddress).create(nft_address,id);
            address pools = getPool721[nft_address][vtokenAddress][tokenB];
            if(pools == address(0)){
                pools= address(new  SwapPool(vtokenAddress,tokenB,address(this),scale));
                getPool721[nft_address][vtokenAddress][tokenB]=pools;
                PoolInfo memory poolInfo= PoolInfo(pools,nft_address,0,vtokenAddress,tokenB,fractionNFTAddress);
                poolInfoArray.push(poolInfo);
                poolMap721[nft_address][tokenB]= poolInfo;
            }

        }
    }

    function addPool721(address nft_address,address tokenB ,uint256 tokenId,uint _amountA,uint _amountB) public {
        address vtokenAddress = FractionNFT(fractionNFTAddress).exchange721(msg.sender,nft_address,tokenId);
        address pools=  getPool721[nft_address][vtokenAddress][tokenB];
        SwapPool(pools).stake(msg.sender,_amountA, _amountB);
        addMyAddPoolMap(msg.sender, pools, nft_address, tokenB);
    }

    function addPoolPositionManager(ICustodyPositionManager.MintParams memory params)public{
        ICustodyPositionManager(custodyPositionManagerAddress).mintNewPosition(msg.sender,params);
    }


    function addPool1155(address nft_address,uint256 id,address tokenB,uint _amountA,uint _amountB)public {
        address vtokenAddress = FractionNFT(fractionNFTAddress).exchange1155(nft_address,id,_amountA);
        address pools=  getPool1155[nft_address][vtokenAddress][tokenB][id];
        SwapPool(pools).stake(msg.sender,_amountA, _amountB);
    }


    function unStake721(address nft_address,address tokenB ,uint lpAmount) public {
        address vtokenAddress = FractionNFT(fractionNFTAddress).getVtokenAddress721(nft_address);
        address pools=  getPool721[nft_address][vtokenAddress][tokenB];
        SwapPool(pools).unStake(msg.sender,lpAmount);
    }


    function unStake1155(address nft_address,uint256 id,address tokenB ,uint lpAmount) public {
        address tokenA = FractionNFT(fractionNFTAddress).getVtokenAddress1155(nft_address,id);
        address pools=  getPool1155[nft_address][tokenA][tokenB][id];
        SwapPool(pools).unStake(msg.sender,lpAmount);
    }

    function addMyAddPoolMap(address owner, address poolsAddress, address nft_address,address tokenB) private {
        if(myAddPoolMap[owner][poolsAddress] == 0){
            myAddPoolMap[owner][poolsAddress] = 1;
            PoolInfo memory poolInfo= PoolInfo(poolsAddress,nft_address,0,tokenB,tokenB,tokenB);
            myAddPoolArr[owner].push(poolInfo);
        }
    }




}
