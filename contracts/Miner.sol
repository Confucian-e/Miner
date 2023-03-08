// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Miner is Ownable, ReentrancyGuard {
    // BSC 链 USDC 地址，精度为 18
    address constant public USDC = 0x31d0ce72C46940DDb5192D6006E8bC0Ca3Ebd805;

    uint constant public elecExpendPerDevice_30days = 1.2195e20;   // 121.95 USDC
    uint constant lockTime = 25 seconds;

    // 用户邀请返佣奖励
    mapping (address => uint) referralBonus;

    // 用户质押的总数
    mapping (address => uint) userTotalDepositAmount;

    // 用户质押的订单数
    mapping (address => uint8) userTotalDepositOrders;

    // 用户 => 用户的订单数组
    mapping (address => Order[]) userOrder;

    // 矿场总矿机台数 Y
    uint private totalDevices;
    // 矿场 30 天总收益 Z
    uint private totalProfit_30days;
    // 积累的手续费，只有管理员能提取
    uint private fees;

    // 返佣比例
    uint private molecular;
    uint private denominator;

    // 订单结构体
    struct Order {
        uint depositAmount;
        uint claimedRewardTime;
        uint endTime;
        uint withdrawTime;
    }

    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event ClaimReward(address indexed user, uint amount);
    event ClaimReferralBonus(address indexed user, uint amount);
    event RedeemFees(address indexed admin, uint amount);

    // ==================================== 用户查看（view public functions） ====================================

    /**
     * @dev 用户现存订单数
     * @param account 用户地址
     */
    function totalDepositOrders(address account) view public returns (uint8) {
        return userTotalDepositOrders[account];
    }

    /**
     * @dev 用户现有质押数
     * @param account 用户地址
     */
    function totalDepositAmount(address account) view public returns (uint) {
        return userTotalDepositAmount[account];
    }

    // =========================================== 质押 ===========================================

    /**
     * @dev 质押
     * @param _depositAmount 质押的数量，最小质押数为 50
     * @param _invitation 上级邀请人地址，没有则填零地址
     */
    function deposit(uint _depositAmount, address _invitation) public {
        require(_depositAmount > 50e18, 'Minimum amount is 50 USDC');
        IERC20(USDC).transferFrom(msg.sender, address(this), _depositAmount);

        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[msg.sender];

        Order memory newOrder = Order(
            _depositAmount,
            block.timestamp,
            block.timestamp + lockTime,
            1
        );

        // 将新的订单加入对应数组
        orders.push(newOrder);

        userTotalDepositOrders[msg.sender]++;                       // 质押总订单数 +1
        userTotalDepositAmount[msg.sender] += _depositAmount;      // 质押总数 + 新的质押数

        if(_invitation != address(0)) referralBonus[_invitation] += _depositAmount * molecular / denominator;   // 邀请人奖励

        emit Deposit(msg.sender, _depositAmount);
    }

    // =========================================== 提取本金 ===========================================

    /**
     * @dev 提取本金
     */
    function withdraw() public nonReentrant {
        require(userTotalDepositOrders[msg.sender] > 0, 'You have no orders');
        require(userTotalDepositAmount[msg.sender] > 0, 'Your deposit amount should exceed zeor');
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[msg.sender];

        uint receiveAmount;
        uint8 count;
        for (uint i = 0; i < orders.length; i++) {
            Order storage targetOrder = orders[i];
            if(targetOrder.endTime <= block.timestamp && targetOrder.withdrawTime == 1) {
                receiveAmount += targetOrder.depositAmount;
                targetOrder.withdrawTime = block.timestamp;

                count++;
            }
            if(targetOrder.endTime > block.timestamp) break;
        }
        require(receiveAmount > 0, 'Withdrawable amount is zero');

        userTotalDepositOrders[msg.sender] -= count;
        userTotalDepositAmount[msg.sender] -= receiveAmount;

        uint actualReceiveAmount = receiveAmount * 97 / 100;
        fees += receiveAmount - actualReceiveAmount;

        IERC20(USDC).transfer(msg.sender, actualReceiveAmount);

        emit Withdraw(msg.sender, actualReceiveAmount);
    }

    // =========================================== 提取收益 ===========================================

    /**
     * @dev 提取收益
     */
    function claimReward() public nonReentrant {
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[msg.sender];

        uint reward;
        for (uint i = 0; i < orders.length; i++) {
            Order storage targetOrder = orders[i];
            if(targetOrder.endTime > block.timestamp) continue;
            uint time = targetOrder.withdrawTime == 1 ? block.timestamp : targetOrder.withdrawTime;
            if(time <= targetOrder.claimedRewardTime) continue;
            reward += (time - targetOrder.claimedRewardTime) / 1 seconds * _calculateRewardPerMinute(targetOrder.depositAmount);
            targetOrder.claimedRewardTime = block.timestamp;
        }

        uint receiveReward = reward * 97 / 100;
        fees += reward - receiveReward;

        IERC20(USDC).transfer(msg.sender, receiveReward);

        emit ClaimReward(msg.sender, receiveReward);
    }

    /**
     * @dev 计算用户的收益，未提取本金的继续计息
     */
    function calculateReward(address account) view public returns (uint reward) {
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[account];
        
        for (uint i = 0; i < orders.length; i++) {
            Order memory targetOrder = orders[i];
            uint time = targetOrder.withdrawTime == 1 ? block.timestamp : targetOrder.withdrawTime;
            if(time <= targetOrder.claimedRewardTime) continue;
            reward += (time - targetOrder.claimedRewardTime) / 1 seconds * _calculateRewardPerMinute(targetOrder.depositAmount);
        }
    }
    

    /**
     * @dev 计算每天的收益
     * @param _depositAmount 质押数量
     */
    function _calculateRewardPerMinute(uint _depositAmount) view private returns (uint rewardPerMinute) {
        (uint _totalDevices, uint _totalProfit_30days) = getDevicesAndProfit();    // gas saving
        rewardPerMinute = _depositAmount * _totalProfit_30days / elecExpendPerDevice_30days  / _totalDevices / 72000;  // 50 * 24 * 60
    }

    // =========================================== 邀请返佣 ===========================================

    /**
     * @dev 查看返佣奖励
     * @param account 用户地址
     */
    function checkReferralBonus(address account) view public returns (uint referral_bonus) {
        referral_bonus = referralBonus[account];
    }

    // 提取返佣奖励
    function claimReferralBonus() external nonReentrant {
        uint referral_bonus = checkReferralBonus(msg.sender);
        require(referral_bonus > 0, 'You have no referral bonus');
        delete referralBonus[msg.sender];
        IERC20(USDC).transfer(msg.sender, referral_bonus);

        emit ClaimReferralBonus(msg.sender, referral_bonus);
    }

    // =========================================== 管理员 ===========================================

    /**
     * @dev 管理员设置 
     * @param _totalDevices 矿场总矿机台数 Y
     * @param _totalProfit_30days 矿场 30 天总收益 Z
     */ 
    function setDevicesAndProfit(uint _totalDevices, uint _totalProfit_30days) external onlyOwner {
        totalDevices = _totalDevices;
        totalProfit_30days = _totalProfit_30days;
    }

    function getDevicesAndProfit() view public returns (uint _totalDevices, uint _totalProfit_30days) {
        _totalDevices = totalDevices;
        _totalProfit_30days = totalProfit_30days;
    }

    // 查看累计的手续费
    function showFees() view public onlyOwner returns (uint) {
        return fees;
    }

    // 提取手续费
    function redeemFees() external onlyOwner {
        uint fee_amount = showFees();
        delete fees;
        IERC20(USDC).transfer(msg.sender, fee_amount);

        emit RedeemFees(msg.sender, fee_amount);
    }

    // 设置返佣比例，分子 - 分母
    function setProportion(uint _molecular, uint _denominator) public onlyOwner {
        molecular = _molecular;
        denominator = _denominator;
    }

    function getProportion() view public returns (uint _molecular, uint _denominator) {
        _molecular = molecular;
        _denominator = denominator;
    }
}