// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import './VToken.sol';

/**
erc721 interface operation
 */
interface ERC721 {
    function approve(address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/**
Erc1155 interface operation
 */
interface ERC1155 {
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IPostionManager {
    function getCurrentTick(address poolAddress) external view returns (int24 tick);
}

contract MidasVault is Ownable, IERC721Receiver {


    // @dev MIN_TICK & MAX_TICK refer to all the range, 
    //      which only used in deposited NFT assets from traders.
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    
    address private custodyPositionManager;
    address private midaswapRouter;
        
    constructor (address _custodyPositionManager) public {
        custodyPositionManager = _custodyPositionManager;
    }
    /**
    nftaddress  => vtoken addrees 
     */
    mapping(address => address) public nftVTokenMap721;
    /**
    nftaddress => id => vtoken address  
     */
    mapping(address => mapping(uint256 => address)) public nftVTokenMap1155;

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

    function setRouter(
        address _midasRouter
    ) external onlyOwner returns (bool) {
        midaswapRouter = _midasRouter;
        return true;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
    get  vtoken address by nft 721 address 
     */
    function getVtokenAddress721(address nftAddress) external view returns (address) {
        return nftVTokenMap721[nftAddress];
    }
    /**
        get vtoken address by  nft 1155 address and  nft  id 
     */
    function getVtokenAddress1155(address nftAddress, uint256 id) external view returns (address) {
        return nftVTokenMap1155[nftAddress][id];
    }
    /**

    /* ========== EXTERNAL FUNCTIONS ========== */

    modifier onlyRouter {
        require(msg.sender == midaswapRouter);
        _;
    }

    function create(
        address nftAddress, 
        uint id
        ) external returns (address) {
            if(id > 0){
                require(nftVTokenMap1155[nftAddress][id] == address(0));
                nftVTokenMap1155[nftAddress][id]= address(new VTOKEN("VTOKEN","VTOKEN"));
                return nftVTokenMap1155[nftAddress][id];
            } else {
                require(nftVTokenMap721[nftAddress] == address(0));
                nftVTokenMap721[nftAddress]= address(new VTOKEN("VTOKEN","VTOKEN"));
                return nftVTokenMap721[nftAddress];
            }
        }

    function exchangeERC721FromLP(
        address owner, 
        address nftAddress, 
        uint256[] calldata tokenId,
        address poolAddress,
        int24 tickLower,
        int24 tickUpper
        ) external payable returns (uint256 nftAmount) {
            // Check if the deposit successful
            require(_depositNFTsFromLP(nftAddress, tokenId, poolAddress, tickLower, tickUpper), "Deposit assets failed!");   
            // Exchange the vToken to LP         
            nftAmount = tokenId.length;
            VTOKEN(nftVTokenMap721[nftAddress]).mint(owner, tokenId.length);
        }

    function exchangeERC721FromTrader(
        address owner, 
        address nftAddress, 
        address poolAddress,
        uint256[] calldata tokenId
        ) external payable returns (uint256 nftAmount) {
            // Check if the deposit successful
            require(_depositNFTsFromTrader(nftAddress, tokenId, poolAddress), "Deposit assets failed!");
            // Exchange the vToken to Trader
            nftAmount = tokenId.length;
            VTOKEN(nftVTokenMap721[nftAddress]).mint(owner, nftAmount);
        }
    
    function withdrawFromFractionsToERC721(
        address nftAddress,
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
        ) external returns (uint256 nftAmount) {
            nftAmount = tokenId.length;
            // Get current tick price
            int24 currentTick = IPostionManager(custodyPositionManager).getCurrentTick(poolAddress);
            // Check if the tokenId is valid to withdraw
            require(_checkTickPrice(poolAddress, tokenId, currentTick), 'Not available for withdraw!');
            require(_checkOwnership(poolAddress, tokenId, receiver), 'Not available for withdraw!');
            // Check if the withdrawal successful
            VTOKEN(nftVTokenMap721[nftAddress]).burn(receiver, nftAmount);
            require(_withdrawNFTs(nftAddress, poolAddress, tokenId, receiver), "Withdraw assets failed!");
        }
    
    function withdrawFromFTtoERC721(
        address nftAddress,
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
        ) external onlyRouter returns (uint256 nftAmount) {
            nftAmount = tokenId.length;
            // Get current tick price
            int24 currentTick = IPostionManager(custodyPositionManager).getCurrentTick(poolAddress);
            // Check if the tokenId is valid to withdraw
            require(_checkTickPrice(poolAddress, tokenId, currentTick), 'Not available for withdraw!');
            VTOKEN(nftVTokenMap721[nftAddress]).burn(receiver, nftAmount);
            require(_withdrawNFTs(nftAddress, poolAddress, tokenId, receiver), "Withdraw assets failed!");
        }    

    function withdrawFromFTtoERC721Conduit(
        address nftAddress,
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
        ) external onlyRouter returns (uint256 nftAmount) {
            nftAmount = tokenId.length;
            require(_withdrawNFTs(nftAddress, poolAddress, tokenId, receiver), "Withdraw assets failed!");
        }   
    
    function withdrawERC721FromLP(
        address nftAddress, 
        address poolAddress, 
        uint256[] calldata tokenId, 
        address receiver
        ) external returns (uint256 nftAmount) {
            nftAmount = tokenId.length;
            // Check if the tokenId is valid to withdraw
            _checkOwnership(poolAddress, tokenId, receiver);
            // Check if the withdrawal successful
            VTOKEN(nftVTokenMap721[nftAddress]).burn(receiver, nftAmount);
            require(_withdrawNFTs(nftAddress, poolAddress, tokenId, receiver), "Withdraw assets failed!");            
        }

    
    function exchangeFromERC1155(
        address nftAddress, 
        uint256 id, 
        uint256 amount,
        address receiver
        ) external payable returns (address) {
            VTOKEN(nftVTokenMap1155[nftAddress][id]).mint(receiver, amount);
            ERC1155(nftAddress).safeTransferFrom(receiver, address(this), id, amount, '0x');
            return nftVTokenMap1155[nftAddress][id];
        }

    function exchangeToERC1155(
        address nftAddress,
        uint256 id,
        uint256 amount,
        address receiver
        ) external returns (address) {
            VTOKEN(nftVTokenMap1155[nftAddress][id]).burn(receiver, amount);
            ERC1155(nftAddress).safeTransferFrom(address(this), receiver, id, amount, '0x');
            return nftVTokenMap1155[nftAddress][id];                        
        }


    struct DepositParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
    }
    
    /// @dev poolAddress => tokenID => DepositParams
    mapping(address => mapping(uint256 => DepositParams)) public deposits;

    function getOwner(
        uint256 tokenId,
        address poolAddress
        ) external view returns(address owner){
            owner = deposits[poolAddress][tokenId].owner;
        }
    
    function checkTickPriceOutside(
        address poolAddress,
        uint256[] calldata tokenId
        ) external view returns (bool) {
            // Get current tick price
            int24 currentTick = IPostionManager(custodyPositionManager).getCurrentTick(poolAddress);
            for (uint i = 0; i < tokenId.length; i++) {
                require(deposits[poolAddress][tokenId[i]].tickLower > currentTick);
            }
            return true;            
        }
    
    /* ========== INTERNAL FUNCTIONS ========== */

    function _checkTickPrice(
        address poolAddress,
        uint256[] calldata tokenId,
        int24 currentTick
        ) internal view returns (bool) {
            for (uint i = 0; i < tokenId.length; i++) {
                require(deposits[poolAddress][tokenId[i]].tickLower <= currentTick && deposits[poolAddress][tokenId[i]].tickUpper >= currentTick);
            }
            return true;
        }

    function _checkOwnership(
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
        ) internal view returns (bool) {
            for (uint i = 0; i < tokenId.length; i++) {
                require(receiver == deposits[poolAddress][tokenId[i]].owner || address(this) == deposits[poolAddress][tokenId[i]].owner);
            }
            return true;        
        }
   
    function _depositSingleNFTFromLP(
        address nftAddress, 
        uint256 tokenId,        
        address poolAddress,
        int24 tickLower,
        int24 tickUpper
        ) internal returns (bool) 
        {
            // Deposit the NFT into Vault
            IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
            // Create a deposit record
            deposits[poolAddress][tokenId] = DepositParams({owner: msg.sender, tickLower: tickLower, tickUpper: tickUpper});
            return true;
        }

    function _depositSingleNFTFromTrader(
        address nftAddress,
        address poolAddress,
        uint256 tokenId
    ) internal returns (bool) {
        // Deposit the NFT into Vault
        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        // Create a deposit record
        deposits[poolAddress][tokenId] = DepositParams({owner: address(this), tickLower: MIN_TICK, tickUpper: MAX_TICK});
        return true;
    }

    function _depositNFTsFromLP(
        address nftAddress,
        uint256[] calldata tokenId,
        address poolAddress,
        int24 tickLower,
        int24 tickUpper
        ) internal returns (bool) 
        {
            for (uint i = 0; i < tokenId.length; i++) {
                // Deposit the NFT into Vault
                IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId[i]);
                // Create a deposit record
                deposits[poolAddress][tokenId[i]] = DepositParams({owner: msg.sender, tickLower: tickLower, tickUpper: tickUpper});
            }
            return true;
        }

    function _depositNFTsFromTrader(
        address nftAddress,
        uint256[] calldata tokenId,
        address poolAddress
        ) internal returns (bool) 
        {
            for (uint i = 0; i < tokenId.length; i++) {
                // Deposit the NFT into Vault
                IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId[i]);
                // Create a deposit record
                deposits[poolAddress][tokenId[i]] = DepositParams({owner: address(this), tickLower: MIN_TICK, tickUpper: MAX_TICK});
            }
            return true;
        }

    function _withdrawSingleNFT(
        address nftAddress,
        address poolAddress,
        uint256 tokenId,
        address receiver
        ) internal returns (bool) {
            // Withdraw NFT from Vault
            IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenId);
            // Delete the deposit record
            delete deposits[poolAddress][tokenId];
            return true;
        }

    function _withdrawNFTs(
        address nftAddress,
        address poolAddress,
        uint256[] calldata tokenId,
        address receiver
        ) internal returns (bool) {
            for (uint i = 0; i < tokenId.length; i++) {
                // Withdraw the NFT from Vault
                IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenId[i]);
                // Delete the deposit record
                delete deposits[poolAddress][tokenId[i]];
            }
            return true;
        }
}
