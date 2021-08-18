// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IPoker {
    function cards(uint256 tokenId) external view returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate);
}

interface ICardSlot {
    function round() external view returns (uint256);

    function teams(uint256 index)external view returns (address owner, string memory name, uint256 deposits, uint256 slots, uint256 minHashRate);
    function ownedTeams(address account) external view returns (uint256);
}

contract CardMine is Ownable, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    uint256 public constant SLOTS_PER_USER = 11;

    address public immutable poker;
    address public immutable pokerToken;

    address public receiveToken = 0x55d398326f99059fF775485246999027B3197955;
    address public fundReceiver = 0x5772e1Cdb6D6240c581792303189851e612c21f1;

    ICardSlot public cardSlot;

    uint256 public rewardPreSecond = 41666666666666666;
    uint256 public expensePerHashRate = 11574074074;

    uint256 public rewardPerHashRateStored;
    uint256 public lastUpdateTime;
    uint256 public totalHashRates;

    struct Slot {
        uint256[] tokens;
        uint256 hashRates;
        address teamAddress;
    }

    struct User {
        Slot[] slots;

        uint256 extraSlots;
        uint256 hashRates;
        uint256 balance;
        uint256 expenses;
        uint256 rewards;
        uint256 rewardPerHashRateReleased;
        uint256 lastUpdateTime;
    }

    mapping(address => User) private _users;

    struct Team {
        uint256 slots;
        uint256 hashRates;
        uint256 rewards;
        uint256 expenses;
    }

    mapping(address => Team) private _teams;

    mapping(uint256 => uint256) public roundStakedTokens;
    mapping(uint256 => uint256) public roundWithdrawnTokens;

    event ReceiveTokenUpdated(address indexed previousAddress, address indexed newAddress);
    event FundReceiverUpdated(address indexed previousAddress, address indexed newAddress);

    event CardSlotInterfaceUpdated(address indexed previousAddress, address indexed newAddress);

    event RewardPreSecondUpdated(uint256 previousValue, uint256 newValue);
    event ExpensePerHashRateUpdated(uint256 previousValue, uint256 newValue);

    event Staked(address indexed account, uint256 slotIndex, uint256[] tokens);
    event Withdrawn(address indexed account, uint256 slotIndex, uint256[] tokens);
    event RewardPaid(address indexed account, uint256 amount);

    event Recharged(address indexed account, uint256 amount);
    event PurchasedExtraSlot(address indexed account, uint256 amount);

    event TeamRewardAdded(address indexed account,address teamAddress,uint256 reward,uint256 expense);
    event TeamExpenseProfitPaid(address indexed account, uint256 amount);
    event TeamRewardProfitPaid(address indexed account, uint256 amount);

    constructor(address poker_, address pokerToken_) {
        poker = poker_;
        pokerToken = pokerToken_;
    }

    modifier updateReward(address account) {
        rewardPerHashRateStored = rewardPerHashRate();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            User storage user = _users[account];
            user.rewards = earned(account);
            user.expenses = expensed(account) > user.balance ? user.balance : expensed(account);
            user.rewardPerHashRateReleased = rewardPerHashRateStored;
            user.lastUpdateTime = block.timestamp;
        }
        _;
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

    function setRewardPreSecond(uint256 newValue) external onlyOwner {
        require(newValue > 0, "New value must be greater than zero");

        uint256 previousValue = rewardPreSecond;
        rewardPreSecond = newValue;

        emit RewardPreSecondUpdated(previousValue, newValue);
    }

    function setExpensePerHashRate(uint256 newValue) external onlyOwner {
        require(newValue > 0, "New value must be greater than zero");

        uint256 previousValue = expensePerHashRate;
        expensePerHashRate = newValue;

        emit ExpensePerHashRateUpdated(previousValue, newValue);
    }

    function users(address account) public view returns (Slot[] memory slots, uint256 extraSlots, uint256 hashRates, uint256 balance, uint256 rewards) {
        require(account != address(0), "Account is the zero address");

        User memory user = _users[account];
        return (user.slots, user.extraSlots, user.hashRates, user.balance, earned(account));
    }

    function teams(address teamAddress) public view returns (uint256 slots, uint256 hashRates, uint256 rewards, uint256 expenses) {
        require(cardSlot.ownedTeams(teamAddress) > 0, "This address does not have team");

        Team memory team = _teams[teamAddress];
        return (team.slots, team.hashRates, team.rewards, team.expenses);
    }

    function extraSlotPrice() public view returns (uint256) {
        User memory user = _users[_msgSender()];
        if (user.extraSlots == 0) {
            return 10 ether;
        }
        return user.extraSlots * 10 ether;
    }

    function rewardPerHashRate() public view returns (uint256) {
        if (totalHashRates > 0) {
            return rewardPerHashRateStored + (((block.timestamp - lastUpdateTime) * rewardPreSecond * 1e18) / totalHashRates);
        }
        return rewardPerHashRateStored;
    }

    function releasedDuration(address account) public view returns (uint256) {
        User memory user = _users[account];
        if (user.hashRates > 0 && user.balance >= expensePerHashRate) {
            uint256 balance = user.balance - user.expenses > 0 ? user.balance - user.expenses : 0;
            return Math.min(block.timestamp, user.lastUpdateTime + balance / (expensePerHashRate * user.hashRates)) - user.lastUpdateTime;
        }
        return 1;
    }

    function rewardDuration(address account) public view returns (uint256) {
        User memory user = _users[account];
        return block.timestamp - user.lastUpdateTime;
    }

    function earned(address account) public view returns (uint256) {
        User memory user = _users[account];
        if (user.balance < expensePerHashRate ) {
            return user.rewards;
        }

        uint256 totalRewards = (user.hashRates * (rewardPerHashRate() - user.rewardPerHashRateReleased)) / 1e18;
        uint256 releasedDurationds = releasedDuration(account);
        uint256 rewardDurations = rewardDuration(account);

        releasedDurationds = releasedDurationds > 0 ? releasedDurationds : 1;
        rewardDurations = rewardDurations > 0 ? rewardDurations : 1;

        return user.rewards + (totalRewards * releasedDurationds) / rewardDurations;
    }

    function expensed(address account) public view returns (uint256) {
        User memory user = _users[account];
        return user.expenses + user.hashRates * expensePerHashRate * (block.timestamp - user.lastUpdateTime);
    }

    function withdraw(uint256 slotIndex) public nonReentrant updateReward(_msgSender()) {
        address owner = _msgSender();

        User storage user = _users[owner];
        require(slotIndex < user.slots.length, "Invalid slot index");

        Slot storage slot = user.slots[slotIndex];
        for (uint256 i = 0; i < slot.tokens.length; i++) {
            IERC721(poker).safeTransferFrom(address(this), owner, slot.tokens[i]);
        }

        emit Withdrawn(owner, slotIndex, slot.tokens);

        user.hashRates -= slot.hashRates;

        Team storage team = _teams[slot.teamAddress];
        team.hashRates -= slot.hashRates;
        team.slots -= 1;

        totalHashRates -= slot.hashRates;

        roundWithdrawnTokens[cardSlot.round()] += slot.tokens.length;

        delete user.slots[slotIndex];
    }

    function getReward() public nonReentrant updateReward(_msgSender()) {
        address account = _msgSender();
        User storage user = _users[account];

        uint256 rewards = user.rewards;
        if (rewards > 0) {
            uint256 expenses = user.expenses;
            user.balance -= (expenses > user.balance ? user.balance : expenses);

            user.expenses = 0;
            user.rewards = 0;

            uint256 teamRewards = rewards / 20;
            uint256 payment = rewards - teamRewards;

            IERC20(pokerToken).safeTransfer(account, payment);
            emit RewardPaid(account, payment);

            for (uint256 i = 0; i < user.slots.length; i++) {
                Slot storage slot = user.slots[i];

                Team storage team = _teams[slot.teamAddress];
                uint256 reward = (teamRewards * slot.hashRates) / user.hashRates;
                uint256 expense = (expenses * slot.hashRates) / user.hashRates / 5;
                team.rewards += reward;
                team.expenses += expense;

                emit TeamRewardAdded(account, slot.teamAddress, reward, expense);
            }
        }
    }

    function exit(uint256 index) external {
        withdraw(index);
        getReward();
    }

    function getTeamExpenseProfit() public nonReentrant updateReward(_msgSender()) {
        address account = _msgSender();
        Team storage team = _teams[account];

        uint256 expenses = team.expenses;
        if (expenses > 0) {
            team.expenses = 0;

            IERC20(receiveToken).safeTransfer(account, expenses);
            emit TeamExpenseProfitPaid(account, expenses);
        }
    }

    function getTeamRewardProfit() public nonReentrant updateReward(_msgSender()) {
        address account = _msgSender();
        Team storage team = _teams[account];

        uint256 rewards = team.rewards;
        if (rewards > 0) {
            team.rewards = 0;

            IERC20(pokerToken).safeTransfer(account, rewards);
            emit TeamRewardProfitPaid(account, rewards);
        }
    }

    function getTeamReward() external {
        getTeamExpenseProfit();
        getTeamRewardProfit();
    }

    function stake(uint256[] memory tokens, uint256 slotIndex, address teamAddress) external nonReentrant updateReward(_msgSender()) {
        require(tokens.length > 0, "Token cannot be empty");

        address account = _msgSender();

        uint256 teamIndex = cardSlot.ownedTeams(teamAddress);
        require(teamIndex > 0, "This address does not have team");

        (, , , uint256 slots, uint256 minHashRate) = cardSlot.teams(teamIndex - 1);

        Team storage team = _teams[teamAddress];
        require(team.slots < slots, "No card slot available in this team");

        tokens = _transferAndSortTokens(account, tokens);

        (uint256 hashRates, uint256 buffHashRates) = _calculateHashRates(tokens);
        require((hashRates + buffHashRates) >= minHashRate, "Under minHashRate");

        User storage user = _users[account];
        if (user.lastUpdateTime == 0) {
            user.lastUpdateTime = block.timestamp;
        }

        Slot storage slot;
        if (slotIndex < user.slots.length) {
            slot = user.slots[slotIndex];
            require(slot.tokens.length == 0, "Must be an empty slot");
        } else {
            require(user.slots.length <= user.extraSlots + SLOTS_PER_USER, "Not enough available slots");
            slot = user.slots.push();
        }

        slot.tokens = tokens;
        slot.hashRates = hashRates + buffHashRates;
        slot.teamAddress = teamAddress;

        user.hashRates += slot.hashRates;

        team.hashRates += slot.hashRates;
        team.slots += 1;

        totalHashRates += slot.hashRates;

        roundStakedTokens[cardSlot.round()] += tokens.length;

        emit Staked(account, slotIndex, tokens);
    }

    function recharge(uint256 amount) external nonReentrant updateReward(_msgSender()) {
        require(amount > 0, "Cannot recharge 0");

        address account = _msgSender();

        User storage user = _users[account];
        user.balance += amount;

        IERC20(receiveToken).safeTransferFrom(account, address(this), amount);
        IERC20(receiveToken).safeTransfer(fundReceiver, (amount * 80) / 100);

        emit Recharged(account, amount);
    }

    function purchaseExtraSlot(uint256 amount) external nonReentrant {
        address account = _msgSender();

        User storage user = _users[account];
        require(user.slots.length >= SLOTS_PER_USER && user.extraSlots + amount <= SLOTS_PER_USER, "Unable to purchase");

        user.extraSlots += amount;

        uint256 weiAmount = amount * extraSlotPrice();
        IERC20(receiveToken).safeTransferFrom(account, address(this), weiAmount);
        IERC20(receiveToken).safeTransfer(fundReceiver, weiAmount);

        emit PurchasedExtraSlot(account, amount);
    }

    function _transferAndSortTokens(address account, uint256[] memory tokens) private returns (uint256[] memory) {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 rank = _calculateRank(tokens[i]);
            if (rank == 1) rank = 14;

            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(_calculateLevel(tokens[i]) == _calculateLevel(tokens[j]), "Level does not match");

                uint256 nextRank = _calculateRank(tokens[j]);
                if (nextRank == 1) nextRank = 14;

                if (rank > nextRank) {
                    uint256 nextTokenId = tokens[j];
                    tokens[j] = tokens[i];
                    tokens[i] = nextTokenId;

                    rank = nextRank;
                } else if(rank == nextRank) {
                    uint256 suit = _calculateSuit(tokens[i]);
                    uint256 nextSuit = _calculateSuit(tokens[j]);
                    if(suit > nextSuit) {
                        uint256 nextTokenId = tokens[j];
                        tokens[j] = tokens[i];
                        tokens[i] = nextTokenId;

                        suit = nextSuit;
                    }
                }
            }

            IERC721(poker).safeTransferFrom(account, address(this), tokens[i]);
        }

        return tokens;
    }

    function _calculateHashRates(uint256[] memory tokens) private view returns (uint256 hashRates, uint256 buffHashRates) {
        require(tokens.length <= 5, "No more than 5 tokens can be placed");

        uint256 buffMul = 0;
        uint256 lastBuff = 0;
        uint256 sameSuitCount = 1;

        uint256[] memory ranks = new uint256[](14);
        uint256[] memory suits = new uint256[](14);

        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 rank, uint256 suit, , uint256 hashRate) = IPoker(poker).cards(tokens[i]);
            hashRates += hashRate;
            if (rank == 0) {
                buffMul = (suit == 1) ? 2 : 1;
                continue;
            }

            ranks[rank]++;

            if (i == 0) {
                suits[rank] = 1;
            } else {
                uint256 lastSuit = _calculateSuit(tokens[i - 1]);
                uint256 lastRank = _calculateRank(tokens[i - 1]);

                sameSuitCount += suit == lastSuit ? 1 : 0;

                if (lastRank == rank) {
                    if (suit == lastSuit) {
                        suits[rank]++;
                    } else if (suits[rank] < 4) {
                        suits[rank] -= suits[rank] >= 1 ? 1 : 0;
                    }
                } else {
                    suits[rank] = 1;
                }

                if (ranks[rank] >= 4) {
                    buffHashRates = suits[rank] >= 4 ? hashRate * 4 * 2 : (hashRate * 4 * 120) / 100;
                } else if (ranks[rank] == 3) {
                    buffHashRates += suits[rank] == 3 ? hashRate * 3 : (hashRate * 3 * 60) / 100;
                    buffHashRates -= lastBuff;
                } else if (ranks[rank] == 2) {
                    lastBuff = suits[rank] == 2 ? (hashRate * 2 * 60) / 100 : (hashRate * 2 * 30) / 100;
                    buffHashRates += lastBuff;
                } else if (i == 4) {
                    if (_calculateRank(tokens[0]) > 0 && _isContinuous(tokens)) {
                        buffHashRates = (sameSuitCount == 5) ? hashRates * 3 : (hashRates * 150) / 100;
                    }
                }
            }
        }

        if (buffMul > 0) {
            buffHashRates += (buffHashRates + hashRates) * buffMul;
        }
    }

    function _isContinuous(uint256[] memory tokens) private pure returns (bool) {
        bool isContinuous = true;

        for (uint256 i = 0; i < tokens.length - 1; i++) {
            uint256 nextRanks = _calculateRank(tokens[i + 1]);
            uint256 currencyRank = _calculateRank(tokens[i]);
            if (currencyRank == 1) {
                currencyRank = 14;
            }
            if (nextRanks == 1) {
                nextRanks = 14;
            }
            if (nextRanks - currencyRank != 1) {
                isContinuous = false;
                break;
            }
        }

        return isContinuous;
    }

    function _calculateRank(uint256 tokenId) private pure returns (uint256) {
        return ((tokenId % 1000) - (tokenId % 10)) / 10;
    }

    function _calculateSuit(uint256 tokenId) private pure returns (uint256) {
        return tokenId % 10;
    }

    function _calculateLevel(uint256 tokenId) private pure returns (uint256) {
        return ((tokenId % 10000) - (tokenId % 1000)) / 1000;
    }
}
