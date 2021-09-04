// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import "./libraries/PancakeLibrary.sol";

interface IPoker {
    function create(address to, uint8 rank, uint8 suit, uint8 level, uint32 hashRate) external returns (uint256 tokenId);
}

interface ICardSlot {
    function opening() external view returns (uint256);
    
    function round() external view returns (uint256);
    function today() external view returns (uint256);
    
    function totalSales() external view returns (uint256);
    function roundSales(uint256 numberOfRound) external view returns (uint256);
}

contract CardStore is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    address public constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public immutable poker;
    address public immutable pokerToken;

    address public receiveToken = 0x55d398326f99059fF775485246999027B3197955;
    address public fundReceiver = 0x76000F17fD34a1cB1Ccd78DF89F89fE1319CAca0;

    ICardSlot public cardSlot;

    uint256 public suitCount = 2;
    uint256 public levelCount = 0;

    uint256 public totalRewards = 100000;
    uint256 public totalSales = 0;

    mapping(address => uint256) public luckyValues;
    mapping(address => uint256) public rewards;
    mapping(address => address) public referrers;

    mapping(uint256 => uint256) public dailySales;
    mapping(uint256 => uint256) public roundSales;

    mapping(uint256 => uint256) public dailyPrice;

    uint256 private _randomNonce = 0;

    mapping(uint256 => uint256[5]) private _percentOfRanks;

    event ReceiveTokenUpdated(address indexed previousAddress, address indexed newAddress);
    event FundReceiverUpdated(address indexed previousAddress, address indexed newAddress);

    event CardSlotInterfaceUpdated(address indexed previousAddress, address indexed newAddress);

    event Purchased(address indexed account, address indexed referrer, uint256 tokenId);
    event Drawn(address indexed account, uint256 tokenId);

    constructor(address poker_, address pokerToken_) {
        poker = poker_;
        pokerToken = pokerToken_;

        _percentOfRanks[1] = [70, 10, 10, 9, 1];
        _percentOfRanks[2] = [70, 5, 5, 15, 5];
        _percentOfRanks[3] = [77, 8, 1, 8, 6];
        _percentOfRanks[4] = [75, 15, 3, 3, 4];
        _percentOfRanks[5] = [1, 30, 30, 19, 20];
        _percentOfRanks[6] = [53, 14, 14, 1, 18];
        _percentOfRanks[7] = [47, 17, 18, 17, 1];
        _percentOfRanks[8] = [28, 1, 13, 23, 35];
        _percentOfRanks[9] = [1, 37, 3, 55, 4];
        _percentOfRanks[10] = [35, 12, 35, 18, 0];
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

    function setCardSlot(address newAddress) external onlyOwner {
        require(newAddress != address(0), "New address is the zero address");

        address previousAddress = address(cardSlot);
        cardSlot = ICardSlot(newAddress);

        emit CardSlotInterfaceUpdated(previousAddress, newAddress);
    }

    function setSuitCount(uint256 value) external onlyOwner {
        require(value <= 4, "Invalid suit count");
        suitCount = value;
    }

    function setLevelCount(uint256 value) external onlyOwner {
        require(value <= 10, "Invalid level count");
        levelCount = value;
    }

    function period() public view returns (uint256) {
        uint256 tempPeriod = cardSlot.today() % 10;
        return tempPeriod > 0 ? tempPeriod : 10;
    }

    function todaySupply() public view returns (uint256) {
        uint256 numberOfRound = cardSlot.round();
        if (numberOfRound == 0) {
            return 0;
        }

        uint256 lastRound = numberOfRound - (numberOfRound % 2 == 0 ? 2 : 1);
        uint256 totalSupply = cardSlot.roundSales(lastRound) * 5;
        if (totalSupply == 0) {
            uint256 previousRoundSales = roundSales[numberOfRound];
            totalSupply = cardSlot.totalSales() * 5;
            if (numberOfRound % 2 == 0) {
                previousRoundSales += roundSales[numberOfRound - 1];
                totalSupply -= cardSlot.roundSales(numberOfRound) * 5;
            }
            totalSupply -= totalSales - previousRoundSales;
        }

        if (totalSupply < 30) {
            uint256 currentRoundSales = roundSales[numberOfRound];
            if (numberOfRound % 2 == 0) {
                currentRoundSales += roundSales[numberOfRound - 1];
            }
            return totalSupply - currentRoundSales;
        }

        uint256 numberOfPeriod = period();
        if (numberOfPeriod % 5 == 0) {
            return totalSupply / 30;
        }
        return (totalSupply * (6 - (numberOfPeriod % 5))) / 30;
    }

    function price(address token) public view returns (uint256) {
        require(token == pokerToken || token == receiveToken, "Invalid token");

        uint256 tokenAmount = 30 ether + period() * 10 ether;
        if (token == receiveToken) {
            return tokenAmount;
        }

        uint256 numberOfDays = cardSlot.today();
        if (token == pokerToken && dailyPrice[numberOfDays] > 0) {
            return dailyPrice[numberOfDays];
        }

        (uint256 reserve0, uint256 reserve1) = PancakeLibrary.getReserves(PANCAKE_FACTORY, receiveToken, WBNB);
        uint256 bnbAmount = tokenAmount * reserve1 / reserve0;

        (reserve0, reserve1) = PancakeLibrary.getReserves(PANCAKE_FACTORY, pokerToken, WBNB);

        return bnbAmount * reserve0 / reserve1;
    }

    function purchase(address token, address referrer) external nonReentrant {
        address account = _msgSender();
        require(!account.isContract(), "Caller cannot be contract address");

        referrer = _checkReferrer(account, referrer);
        if (referrer != address(0) && IERC721(poker).balanceOf(referrer) >= 1 && totalRewards > 0) {
            rewards[referrer]++;
            totalRewards--;
        }

        uint256 numberOfRound = cardSlot.round();
        require(numberOfRound > 0, "Not yet on sale");

        uint256 numberOfDays = cardSlot.today();
        require(dailySales[numberOfDays] < todaySupply(), "Insufficient supply");

        (uint8 rank, uint8 suit, uint8 level, uint32 hashRate) = _createCardValues();
        uint256 tokenId = IPoker(poker).create(account, rank, suit, level, hashRate);

        dailySales[numberOfDays]++;

        roundSales[numberOfRound]++;

        totalSales++;

        uint256 payment = price(token);
        if (token == pokerToken && dailyPrice[numberOfDays] == 0) {
            dailyPrice[numberOfDays] = payment;
        }
        IERC20(token).safeTransferFrom(account, fundReceiver, payment);

        emit Purchased(account, referrer, tokenId);
    }

    function draw() external nonReentrant {
        address account = _msgSender();
        require(rewards[account] > 0, "Insufficient rewards");

        rewards[account]--;

        uint256 tokenId = 0;

        (uint256 random, uint256 luckyValue) = (_random(100), luckyValues[account]);
        if (random <= 20 || luckyValue == 100) {
            luckyValues[account] = 0;

            uint8 rank = 3;

            random = _random(100);
            if (random >= 80) {
                uint8[5] memory ranks = [7, 8, 9, 11, 13];
                rank = ranks[_random(100) % 5];
            } else if (random >= 50) {
                rank = 5;
            }

            uint8 suit = uint8(random % suitCount);

            tokenId = IPoker(poker).create(account, rank, suit, 0, 10 * rank);
        } else {
            luckyValues[account] += 20;
        }

        emit Drawn(account, tokenId);
    }

    function _createCardValues() internal returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate) {
        uint256 random = _random(100);

        suit = uint8(random % suitCount);
        level = uint8(levelCount > 0 ? random % levelCount : 0);

        uint256 totalSupply = IERC721Enumerable(poker).totalSupply();
        if (totalSupply > 0 && (totalSupply % 1000) == 0) {
            return (0, 1, level, 200);
        } else if (totalSupply > 0 && (totalSupply % 500) == 0) {
            return (0, 0, level, 100);
        }

        uint8[5] memory ranks = [1, 2, 3, 4, 5];

        uint256 numberOfPeriod = period();
        uint256 percentage = 0;

        for (uint256 i = 0; i < ranks.length; i++) {
            uint256 tempRank = (uint256(ranks[i]) + numberOfPeriod) % 14;
            ranks[i] = (tempRank > 0) ? uint8(tempRank) : 1;

            percentage += _percentOfRanks[numberOfPeriod][i];
            if (random <= percentage) {
                rank = ranks[i];
                break;
            }
        }

        hashRate = (rank == 1) ? 150 : 10 * rank;
    }

    function _checkReferrer(address account, address referrer) internal returns (address) {
        if (referrers[account] == address(0) && referrer != address(0) && referrers[referrer] != account && referrer != account) {
            referrers[account] = referrer;
        }
        return referrers[account];
    }

    function _random(uint256 modulus) internal returns (uint256) {
        _randomNonce++;
        return (uint256(keccak256(abi.encodePacked(_randomNonce, block.difficulty, _msgSender()))) % modulus) + 1;
    }
}
