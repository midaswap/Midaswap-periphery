// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNft is ERC721, ERC721URIStorage, Ownable {
    constructor() ERC721("MyAzuki", "MTK") {}

    mapping (address=>uint256) private  addressNftMap;

    mapping (uint256=>string) private  tokenIdUrl;

    mapping (address=>NftInfo[]) private  addressNftInfListMap;



    struct NftInfo{
         uint256 tokenId;
         string  uri;
    }

    function safeMint(address to, uint256 tokenId, string memory uri)
        public
        onlyOwner
    {
        tokenIdUrl[tokenId]=uri;
        _mint(to, tokenId);
       _setTokenURI(tokenId, uri);
      
    }

   function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override   {
        if(from == address(0)){
            addNft(to, firstTokenId,tokenIdUrl[firstTokenId]);
        }else {
            addNft(to, firstTokenId, tokenIdUrl[firstTokenId]);
            delNft(from,firstTokenId);
        }
    }
    

    function getNftInfoList(address owner_)public  view  returns(NftInfo[] memory) {
        return  addressNftInfListMap[owner_];
    }

    
    function  delNft(address to,uint256 tokenId) private {
         NftInfo[] memory nftInfoList= addressNftInfListMap[to];
         for (uint256 index = 0; index < nftInfoList.length; index++) {
             if(nftInfoList[index].tokenId == tokenId){
                  if (index == nftInfoList.length - 1) {
                      addressNftInfListMap[to].pop();
                  }else{
                        addressNftInfListMap[to][index] = addressNftInfListMap[to][nftInfoList.length - 1];
                        addressNftInfListMap[to].pop();
                  }
             }
         }
    }

   function  addNft(address to,uint256 tokenId,string memory uri) private {
        addressNftInfListMap[to].push(NftInfo(tokenId,uri));
    }


    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

}