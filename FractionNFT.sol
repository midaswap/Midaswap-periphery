// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;


import "./VToken.sol";
/**
erc721 interface operation
 */
interface Erc721 {
    function approve(address to, uint256 tokenId) external;
    function transferFrom(  address from, address to, uint256 tokenId ) external;
}

/**
Erc1155 interface operation
 */
interface Erc1155 {
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom ( address from, address to, uint256 id,  uint256 amount,  bytes memory data) external;
}

contract FractionNFT  {
    /**
    nftaddress  => vtoken addrees 
     */
    mapping(address =>address) nftVTokenMap721;
    /**
    nftaddress => id => vtoken address  
     */
    mapping(address =>mapping(uint256 =>address)) nftVTokenMap1155;

    /**
    get  vtoken address by nft 721 address 
     */
    function getVtokenAddress721(address nftAddress)public view returns(address) {
        return nftVTokenMap721[nftAddress];
    }
    /**
        get vtoken address by  nft 1155 address and  nft  id 
     */
    function getVtokenAddress1155(address nftAddress,uint256 id)public view returns(address) {
        return nftVTokenMap1155[nftAddress][id];
    }
    /**
    
      create vtoken , if id gt 0  create 1155 vtoken or eq 0  create 721 voken
     */
    function create(address nftAddress,uint  id ) public returns(address) {
        if(id >0 ){
            require(nftVTokenMap1155[nftAddress][id] == address(0));
            nftVTokenMap1155[nftAddress][id]= address(new  VTOKEN("VTOKEN","VTOKEN"));
            return nftVTokenMap1155[nftAddress][id];
        }else{
            require(nftVTokenMap721[nftAddress] == address(0));
            nftVTokenMap721[nftAddress]= address(new  VTOKEN("VTOKEN","VTOKEN"));
            return nftVTokenMap721[nftAddress];
        }
    }

    /**
      change nft to  721 votken
     */
    function exchange721(address owner, address nftAddress,uint256 tokenId )public returns(address){
        VTOKEN(nftVTokenMap721[nftAddress]).mint(owner, 1 ether);
        Erc721(nftAddress).transferFrom(owner, address(this), tokenId);
        return nftVTokenMap721[nftAddress];
    }

    /**
    
      change nft to  1155 votken
     */
    function exchange1155(address nftAddress,uint256 id, uint256 amount)public  returns(address){
        VTOKEN(nftVTokenMap1155[nftAddress][id]).mint(msg.sender, amount);
        Erc1155(nftAddress).safeTransferFrom(msg.sender, address(this), id,amount,'0x');
        return nftVTokenMap1155[nftAddress][id];
    }

}
