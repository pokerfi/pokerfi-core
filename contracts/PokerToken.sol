// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

abstract contract Whitelisted is Ownable {
    event WhitelistedAdded(address indexed account);
    event WhitelistedRemoved(address indexed account);

    mapping(address => bool) private _whitelisteds;

    modifier onlyWhitelisted() {
        require(isWhitelisted(_msgSender()), "Caller is not whitelisted");
        _;
    }

    function isWhitelisted(address account) public view returns (bool) {
        return _whitelisteds[account] || account == owner();
    }

    function addWhitelisted(address account) external onlyOwner {
        _addWhitelisted(account);
    }

    function removeWhitelisted(address account) external onlyOwner {
        _removeWhitelisted(account);
    }

    function renounceWhitelisted() external {
        _removeWhitelisted(_msgSender());
    }

    function _addWhitelisted(address account) internal {
        _whitelisteds[account] = true;
        emit WhitelistedAdded(account);
    }

    function _removeWhitelisted(address account) internal {
        delete _whitelisteds[account];
        emit WhitelistedRemoved(account);
    }
}

contract PokerToken is Whitelisted, ERC20, ERC20Burnable {
    using Address for address;

    uint256 public constant MAX_SUPPLY = 21_000_000e18;

    IUniswapV2Router02 public constant UNISWAPV2_ROUTER = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public immutable uniswapV2Pair;

    struct FeeRate {
        uint8 burn;
        uint8 liquidity;
        uint8 reward;
    }

    FeeRate public feeRate;

    uint256 public totalLiquidity;
    uint256 public totalShares;
    uint256 public rewardPerShare;

    mapping(address => uint256) public shares;
    mapping(address => uint256) public lastRewardPerShare;

    event FeeRateUpdated(uint8 previousBurnRate, uint8 previousLiquidityRate, uint8 previousRewardRate, uint8 newBurnRate, uint8 newLiquidityRate, uint8 newRewardRate);

    event Released(address indexed account, uint256 amount);

    constructor() ERC20("PokerFi Token", "PK") {
        uniswapV2Pair = IUniswapV2Factory(UNISWAPV2_ROUTER.factory()).createPair(address(this), UNISWAPV2_ROUTER.WETH());

        feeRate.burn = 3;
        feeRate.liquidity = 3;
        feeRate.reward = 4;
    }

    receive() external payable {
    }

    function setFeeRate(uint8 newBurnRate, uint8 newLiquidityRate, uint8 newRewardRate) external onlyOwner {
        require(newBurnRate + newLiquidityRate + newRewardRate <= 100, "Invalid fee rate");

        uint8 previousBurnRate = feeRate.burn;
        uint8 previousLiquidityRate = feeRate.liquidity;
        uint8 previousRewardRate = feeRate.reward;

        feeRate.burn = newBurnRate;
        feeRate.liquidity = newLiquidityRate;
        feeRate.reward = newRewardRate;

        emit FeeRateUpdated(previousBurnRate, previousLiquidityRate, previousRewardRate, newBurnRate, newLiquidityRate, newRewardRate);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        require(amount + totalSupply() <= MAX_SUPPLY, "Max supply exceeded");
        _mint(account, amount);
    }

    function releasable(address account) public view returns (uint256) {
        if (shares[account] == 0 || rewardPerShare == 0) {
            return 0;
        }
        return shares[account] * (rewardPerShare - lastRewardPerShare[account]) / 1e18;
    }

    function release(address account) public {
        uint256 amount = releasable(account);
        if (amount > 0) {
            _transfer(address(this), account, amount);
            emit Released(account, amount);
        }

        lastRewardPerShare[account] = rewardPerShare;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (feeRate.burn > 0 || feeRate.liquidity > 0 || feeRate.reward > 0) {
            if ((sender == address(UNISWAPV2_ROUTER) || sender == uniswapV2Pair) && !isWhitelisted(recipient)) {
                release(recipient);

                shares[recipient] += amount;
                totalShares += amount;
            }

            if (!isWhitelisted(sender) && (recipient == address(UNISWAPV2_ROUTER) || recipient == uniswapV2Pair)) {
                (uint256 burnAmount, uint256 liquidityAmount, uint256 rewardAmount) = _calculateFee(amount);

                super._transfer(sender, address(this), burnAmount + liquidityAmount + rewardAmount);

                if (totalShares == 0) {
                    liquidityAmount += rewardAmount;
                } else {
                    rewardPerShare += rewardAmount * 1e18 / totalShares;
                }

                _burn(address(this), burnAmount);
                _addLiquidity(liquidityAmount);
            }

            uint256 senderBalance = balanceOf(sender);
            if ((sender != address(UNISWAPV2_ROUTER) || sender != uniswapV2Pair) && shares[sender] >= senderBalance) {
                release(sender);

                uint256 deductedShares = (senderBalance == amount) ? shares[sender] : amount;
                shares[sender] -= deductedShares;
                totalShares -= deductedShares;
            }
        }

        super._transfer(sender, recipient, amount);
    }

    function _addLiquidity(uint256 amount) private {
        totalLiquidity += amount;
        if (totalLiquidity >= 1e18) {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = UNISWAPV2_ROUTER.WETH();

            uint256 ethBalance = address(this).balance;
            if (ethBalance > 1e16 && totalShares > 0) {
                uint256 lastTokenBalance = balanceOf(address(this)) - totalLiquidity;
                UNISWAPV2_ROUTER.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethBalance}(0, path, address(this), block.timestamp);
                rewardPerShare += (balanceOf(address(this)) - lastTokenBalance) * 1e18 / totalShares;
            }

            _approve(address(this), address(UNISWAPV2_ROUTER), totalLiquidity);

            uint256 liquidityAmount = totalLiquidity / 2;
            totalLiquidity = 0;

            UNISWAPV2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(liquidityAmount, 0, path, address(this), block.timestamp);

            UNISWAPV2_ROUTER.addLiquidityETH{value: address(this).balance}(address(this), liquidityAmount, 0, 0, owner(), block.timestamp);
        }
    }

    function _calculateFee(uint256 amount) private view returns (uint256 burnFee, uint256 liquidityFee, uint256 rewardFee) {
        return (amount * feeRate.burn / 100, amount * feeRate.liquidity / 100, amount * feeRate.reward / 100);
    }
}
