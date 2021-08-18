// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IPoker {
    function cards(uint256 tokenId) external view returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate);
}

contract CardMarket is Ownable, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    address public immutable poker;

    address public receiveToken = 0x55d398326f99059fF775485246999027B3197955;
    address public fundReceiver = 0xA883795C2fa5D62d8517702fdc45fAAe811DE8de;

    uint256 public feeRate = 0;

    struct Card {
        address user;

        uint256 tokenId;
        uint256 price;

        uint8 rank;
        uint8 suit;
        uint8 level;
    }

    Card[] private _cards;

    mapping(uint256 => uint256) private _allCard;

    event ReceiveTokenUpdated(address indexed previousAddress, address indexed newAddress);
    event FundReceiverUpdated(address indexed previousAddress, address indexed newAddress);
    
    event FeeRateUpdated(uint256 previousValue, uint256 newValue);
    
    event Sold(address indexed account, uint256 tokenId, uint256 price);
    event Bought(address indexed account, address indexed seller, uint256 tokenId, uint256 price, uint256 level, uint256 rank, uint256 suit);
    event Withdrawn(address indexed account, uint256 tokenId, uint256 level, uint256 rank, uint256 suit);

    constructor(address poker_) {
        poker = poker_;
    }

    function setReceiveToken(address newAddress) external onlyOwner {
        require(newAddress != address(0), "New address is the zero address");

        address previousAddress = receiveToken;
        receiveToken = newAddress;

        emit ReceiveTokenUpdated(previousAddress, newAddress);
    }

    function setFundReceiver(address newAddress) external onlyOwner {
        require(newAddress != address(0), "New address is the zero address");

        address previousAddress = fundReceiver;
        fundReceiver = newAddress;

        emit FundReceiverUpdated(previousAddress, newAddress);
    }

    function setFeeRate(uint256 newValue) external onlyOwner {
        require(newValue < 100, "Invalid fee rate");
        
        uint256 previousValue = feeRate;
        feeRate = newValue;
        
        emit FeeRateUpdated(previousValue, newValue);
    }

    function totalCards() public view returns (uint256) {
        return _cards.length;
    }

    function cards(uint256 startIndex, uint256 endIndex) public view returns (Card[] memory) {
        if (endIndex == 0 || endIndex > totalCards()) {
            endIndex = totalCards();
        }
        require(startIndex < endIndex, "Invalid index");

        Card[] memory result = new Card[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = _cards[i];
        }
        return result;
    }

    function sell(uint256 tokenId, uint256 price) external nonReentrant {
        address account = _msgSender();

        (uint8 rank, uint8 suit, uint8 level, ) = IPoker(poker).cards(tokenId);
        _cards.push(Card(account, tokenId, price, rank, suit, level));

        _allCard[tokenId] = _cards.length - 1;

        IERC721(poker).safeTransferFrom(account, address(this), tokenId);

        emit Sold(account, tokenId, price);
    }

    function buy(uint256 tokenId) external nonReentrant {
        address account = _msgSender();

        uint256 tokenIndex = _allCard[tokenId];
        Card storage card = _cards[tokenIndex];

        uint256 payment = card.price;
        IERC20(receiveToken).transferFrom(account, address(this), payment);

        address seller = card.user;
        if (feeRate > 0 && fundReceiver != address(0)) {
            uint256 fee = payment * feeRate / 100;
            payment -= fee;

            IERC20(receiveToken).safeTransfer(fundReceiver, fee);
        }
        IERC20(receiveToken).safeTransfer(seller, payment);

        IERC721(poker).safeTransferFrom(address(this), account, tokenId);

        emit Bought(account, seller, tokenId, card.price, card.level, card.rank, card.suit);

        if (_cards.length - 1 > 0 && tokenIndex != _cards.length - 1) {
            Card memory lastCard = _cards[_cards.length - 1];
            card.level = lastCard.level;
            card.price = lastCard.price;
            card.rank = lastCard.rank;
            card.suit = lastCard.suit;
            card.user = lastCard.user;
            card.tokenId = lastCard.tokenId;

            _allCard[lastCard.tokenId] = tokenIndex;
        }

        _cards.pop();

        delete _allCard[tokenId];
    }

    function withdraw(uint256 tokenId) external nonReentrant {
        address account = _msgSender();

        uint256 tokenIndex = _allCard[tokenId];
        Card storage card = _cards[tokenIndex];

        address seller = card.user;
        require(account == seller, "tokenId not owned");

        IERC721(poker).safeTransferFrom(address(this), account, tokenId);

        emit Withdrawn(account, tokenId, card.level, card.rank, card.suit);

        if (_cards.length - 1 > 0 && tokenIndex != _cards.length - 1) {
            Card memory lastCard = _cards[_cards.length - 1];
            card.level = lastCard.level;
            card.price = lastCard.price;
            card.rank = lastCard.rank;
            card.suit = lastCard.suit;
            card.user = lastCard.user;
            card.tokenId = lastCard.tokenId;

            _allCard[lastCard.tokenId] = tokenIndex;
        }

        _cards.pop();

        delete _allCard[tokenId];
    }
}
