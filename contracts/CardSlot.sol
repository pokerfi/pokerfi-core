// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./libraries/PancakeLibrary.sol";

interface ICardMine {
    function roundStakedTokens(uint256 numberOfDays) external view returns (uint256);
    function roundWithdrawnTokens(uint256 numberOfDays) external view returns (uint256);
}

contract CardSlot is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    address public constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address public immutable poker;
    address public immutable pokerToken;

    address public receiveToken = 0x55d398326f99059fF775485246999027B3197955;
    address public fundReceiver = 0x587fcAbB403f617c965637870db5514d40856e4c;

    ICardMine public cardMine;

    uint256 public opening;
    uint256 public basePrice = 50 ether;
    uint256 public totalSales;

    struct Team {
        address owner;

        string name;

        uint256 deposits;
        uint256 slots;
        uint256 minHashRate;
    }

    Team[] private _teams;

    mapping(address => mapping(uint256 => uint256)) public teamRoundDeposits;
    mapping(address => mapping(uint256 => uint256)) public teamRoundSlots;

    mapping(string => uint256) public teamIndexes;
    mapping(address => uint256) public ownedTeams;

    mapping(uint256 => uint256) public roundDeposits;
    mapping(uint256 => uint256) public roundSales;

    event ReceiveTokenUpdated(address indexed previousAddress, address indexed newAddress);
    event FundReceiverUpdated(address indexed previousAddress, address indexed newAddress);

    event CardMineInterfaceUpdated(address indexed previousAddress, address indexed newAddress);

    event BasePriceUpdated(uint256 previousValue, uint256 newValue);

    event Registered(address indexed account, string name);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Purchased(address indexed account, uint256 amount);

    event TeamNameUpdated(address indexed account, string name);
    event MinHashRateChanged(address indexed account, uint256 amount);

    constructor(address pokerToken_, address poker_) {
        pokerToken = pokerToken_;
        poker = poker_;

        fundReceiver = _msgSender();

        opening = block.timestamp;
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

    function setCardMine(address newAddress) external onlyOwner {
        require(newAddress != address(0), "New address is the zero address");

        address previousAddress = address(cardMine);
        cardMine = ICardMine(newAddress);

        emit CardMineInterfaceUpdated(previousAddress, newAddress);
    }

    function setBasePrice(uint256 newValue) external onlyOwner {
        require(newValue >= 1e18, "Invalid value");

        uint256 previousValue = basePrice;
        basePrice = newValue;

        emit BasePriceUpdated(previousValue, newValue);
    }

    function today() public view returns (uint256) {
        return (block.timestamp - opening) / 1 days + 1;
    }

    function period() public view returns (uint256) {
        uint256 numberOfPeriod = today() % 5;
        return numberOfPeriod > 0 ? numberOfPeriod : 5;
    }

    function round() public view returns (uint256) {
        return (block.timestamp - opening) / (5 * 1 days);
    }

    function teams(uint256 index) public view returns (address owner, string memory name, uint256 deposits, uint256 slots, uint256 minHashRate) {
        require(index < _teams.length, "Invalid index");

        Team memory team = _teams[index];
        return (team.owner, team.name, team.deposits, team.slots, team.minHashRate);
    }

    function totalTeams() public view returns (uint256) {
        return _teams.length;
    }

    function teamsByIndex(uint256 startIndex, uint256 endIndex) public view returns (Team[] memory) {
        if (endIndex == 0 || endIndex > totalTeams()) {
            endIndex = totalTeams();
        }
        require(startIndex < endIndex, "Invalid index");

        Team[] memory result = new Team[](endIndex - startIndex);
        uint256 resultLength = result.length;
        uint256 index = startIndex;
        for (uint256 i = 0; i < resultLength; i++) {
            result[i].owner = _teams[index].owner;
            result[i].name = _teams[index].name;
            result[i].deposits = _teams[index].deposits;
            result[i].slots = _teams[index].slots;
            result[i].minHashRate = _teams[index].minHashRate;
            index++;
        }
        return result;
    }

    function price() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = PancakeLibrary.getReserves(PANCAKE_FACTORY, receiveToken, WBNB);
        uint256 bnbAmount = basePrice * reserve1 / reserve0;

        (reserve0, reserve1) = PancakeLibrary.getReserves(PANCAKE_FACTORY, pokerToken, WBNB);

        return bnbAmount * reserve0 / reserve1;
    }

    function currentSupply() public view returns (uint256) {
        uint256 numberOfRound = round();
        if (numberOfRound == 0) {
            return 15000;
        } else if (numberOfRound % 2 == 1) {
            return 0;
        }

        uint256 lastRoundSales = roundSales[numberOfRound - 2];

        uint256 roundStakedTokens = cardMine.roundStakedTokens(numberOfRound);
        uint256 roundWithdrawnTokens = cardMine.roundWithdrawnTokens(numberOfRound);

        uint256 percentage = (
            (IERC721(poker).balanceOf(address(cardMine)) + roundWithdrawnTokens - roundStakedTokens) * 100
        ) / ((totalSales - roundSales[numberOfRound] - lastRoundSales / 2) * 5);

        if (percentage >= 40 && lastRoundSales == 0) {
            lastRoundSales = 2000;
        }

        if (percentage >= 80) {
            return (lastRoundSales * 120) / 100;
        } else if (percentage >= 60) {
            return (lastRoundSales * 80) / 100;
        } else if (percentage >= 40) {
            return (lastRoundSales * 40) / 100;
        }

        return 0;
    }

    function setTeamName(string calldata name) external {
        address account = _msgSender();

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "User can't operation team");

        require(bytes(name).length > 0, "Name cannot be empty");
        require(teamIndexes[name] == 0, "This team already exists");

        Team storage team = _teams[teamIndex - 1];

        teamIndexes[name] = teamIndexes[team.name];
        delete teamIndexes[team.name];

        team.name = name;

        emit TeamNameUpdated(account, name);
    }

    function setMinHashRate(uint256 amount) external {
        address account = _msgSender();

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Not own team");

        _teams[teamIndex - 1].minHashRate = amount;

        emit MinHashRateChanged(account, amount);
    }

    function preOrder(uint256 amount, string calldata name) external nonReentrant {
        uint256 numberOfRound = round();
        require(numberOfRound % 2 == 0 && period() <= 3, "Pre-order has not yet started");

        address account = _msgSender();

        Team storage team;

        uint256 teamIndex = ownedTeams[account];
        if (teamIndex == 0) {
            require(bytes(name).length > 0, "Name cannot be empty");
            require(teamIndexes[name] == 0, "This team already exists");

            team = _teams.push();
            team.owner = account;
            team.name = name;

            teamIndexes[name] = _teams.length;
            ownedTeams[account] = _teams.length;

            emit Registered(account, name);
        } else {
            team = _teams[teamIndex - 1];
        }

        team.deposits += amount;

        teamRoundDeposits[team.owner][numberOfRound] += amount;

        roundDeposits[numberOfRound] += amount;

        IERC20(pokerToken).safeTransferFrom(account, address(this), amount);

        emit Deposited(account, amount);
    }

    function withdraw() external nonReentrant {
        uint256 remainder = round() % 2;
        require(remainder > 0 || (remainder == 0 && period() > 3), "Withdrawal is not allowed at the current time");

        address account = _msgSender();

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Do not own team");

        Team storage team = _teams[teamIndex - 1];

        uint256 payment = team.deposits;
        if (payment > 0) {
            team.deposits = 0;

            IERC20(pokerToken).safeTransfer(account, payment);
        }

        emit Withdrawn(account, payment);
    }

    function purchase(uint256 amount) external nonReentrant {
        uint256 numberOfRound = round();
        uint256 numberOfPeriod = period();

        require(numberOfRound % 2 == 0 && numberOfPeriod > 3, "Not yet on sale");
        require((roundSales[numberOfRound] + amount) <= currentSupply(), "Insufficient supply");

        address account = _msgSender();
        require(!account.isContract(), "Caller cannot be contract address");

        uint256 payment = price() * amount;
        IERC20(pokerToken).safeTransferFrom(account, fundReceiver, payment);

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Not own team");

        Team storage team = _teams[teamIndex - 1];
        team.slots += amount;

        if (numberOfPeriod == 4) {
            uint256 canBePurchased = (teamRoundDeposits[team.owner][numberOfRound] * currentSupply()) / roundDeposits[numberOfRound];
            require(teamRoundSlots[team.owner][numberOfRound] + amount <= canBePurchased, "Purchase limit exceeded");
        }

        team.minHashRate = 100;

        teamRoundSlots[team.owner][numberOfRound] += amount;

        roundSales[numberOfRound] += amount;

        totalSales += amount;

        emit Purchased(account, amount);
    }
}
