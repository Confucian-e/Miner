// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Miner is Ownable, ReentrancyGuard {
    // BSC 链 USDC 地址，精度为 18
    address constant public USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    uint constant public elecExpendPerDevice_30days = 1.2195e20;   // 121.95 USDC

    // 用户邀请返佣奖励
    mapping (address => uint) referralBonus;

    // 用户质押的总数。区分 15/30，false 代表 15，true 代表 30
    mapping (bool => mapping (address => uint)) userTotalDepositAmount;

    // 用户质押的订单数。区分 15/30，false 代表 15，true 代表 30
    mapping (bool => mapping (address => uint8)) userTotalDepositOrders;

    // 15/30 => 用户 => 用户的订单数组
    mapping (bool => mapping (address => Order[])) userOrder;

    // 矿场总矿机台数 Y
    uint private totalDevices;
    // 矿场 30 天总收益 Z
    uint private totalProfit_30days;
    // 积累的手续费，只有管理员能提取
    uint private fees;

    struct Order {
        uint depositAmount;
        uint lastUpdateTime;
        uint endTime;
        //建议改为withdrawReward，当收益全部取完之后可以将订单下架
        bool withdrawn;     // false 表示还未提取本金，true 表示已经提取本金
        bool withdrawReward;
    }

    event Deposit(address indexed user, uint amount, uint8 lockDays);
    event Withdraw(address indexed user, uint amount, uint8 lockDays);
    event ClaimReward(address indexed user, uint amount, uint8 lockDays);
    event ClaimReferralBonus(address indexed user, uint amount);
    event RedeemFees(address indexed admin, uint amount);

    // ==================================== 用户查看（view external functions） ====================================

    function totalDepositOrders15days() view external returns (uint8) {
        return _totalDepositOrders(false);
    }

    function totalDepositOrders30days() view external returns (uint8) {
        return _totalDepositOrders(true);
    }

    function _totalDepositOrders(bool _style) view private returns (uint8) {
        return userTotalDepositOrders[_style][msg.sender];
    }


    function totalDepositAmount15days() view external returns (uint) {
        return _totalDepositAmount(false);
    }

    function totalDepositAmount30days() view external returns (uint) {
        return _totalDepositAmount(true);
    }

    function _totalDepositAmount(bool _style) view private returns (uint) {
        return userTotalDepositAmount[_style][msg.sender];
    }


    function calculateReward15days() view external returns (uint) {
        return _calculateReward(false);
    }

    function calculateReward30days() view external returns (uint) {
        return _calculateReward(true);
    }

    // =========================================== 质押 ===========================================

    function deposit15days(uint _depositAmount, address _invitation) external {
        _deposit(false, _depositAmount, _invitation);
    }

    function deposit30days(uint _depositAmount, address _invitation) external {
        _deposit(true, _depositAmount, _invitation);
    }

    /**
     * @dev 质押
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     * @param _depositAmount 质押的数量
     */
    function _deposit(bool _style, uint _depositAmount, address _invitation) private {
        require(_depositAmount > 0, 'Your deposit amount should exceed zero');
        IERC20(USDC).transferFrom(msg.sender, address(this), _depositAmount);

        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[_style][msg.sender];

        uint8 lockDays = _style ? 30 : 15;
        Order memory newOrder = Order(
            _depositAmount,
            block.timestamp,
            block.timestamp + lockDays * 1 days,
            false,
            false
        );

        // 将新的订单加入对应数组
        orders.push(newOrder);

        userTotalDepositOrders[_style][msg.sender]++;                       // 质押总订单数 +1
        userTotalDepositAmount[_style][msg.sender] += _depositAmount;      // 质押总数 + 新的质押数

        if(_invitation != address(0)) referralBonus[_invitation] += _depositAmount / 100;   // 邀请人奖励，1%

        emit Deposit(msg.sender, _depositAmount, lockDays);
    }

    // =========================================== 提取本金 ===========================================

    function withdraw15days() external {
        _withdraw(false);
    }

    function withdraw30days() external {
        _withdraw(true);
    }

    /**
     * @dev 提取本金
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     */
    function _withdraw(bool _style) private nonReentrant {
        require(userTotalDepositOrders[_style][msg.sender] > 0, 'You have no orders');
        require(userTotalDepositAmount[_style][msg.sender] > 0, 'Your deposit amount should exceed zeor');
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[_style][msg.sender];

        uint receiveAmount;
        uint count; //统计移除的订单数
        for (uint i = 0; i < orders.length; i++) {
            Order storage targetOrder = orders[i];
            if(targetOrder.endTime <= block.timestamp && !targetOrder.withdrawn) {
                receiveAmount += targetOrder.depositAmount;
                targetOrder.withdrawn = true;

                userTotalDepositOrders[_style][msg.sender]--;
                userTotalDepositAmount[_style][msg.sender] -= receiveAmount;
            }
            if(targetOrder.endTime > block.timestamp) continue;//改为continue，因为订单不可能是按照顺序排好的
            if(targetOrder.withdrawReward) {
                orders[i] = orders[orders.length - 1];
                count++;
            }
        }
        for(uint i = 0; i < count; i++){
            orders.pop();
        }
        uint actualReceiveAmount = receiveAmount * 97 / 100;
        fees += receiveAmount - actualReceiveAmount;

        IERC20(USDC).transfer(msg.sender, actualReceiveAmount);

        uint8 lockDays = _style ? 30 : 15;
        emit Withdraw(msg.sender, actualReceiveAmount, lockDays);
    }

    // =========================================== 提取收益 ===========================================
    
    function claimReward15days() external {
        _claimReward(false);
    }

    function claimReward30days() external {
        _claimReward(true);
    }

    /**
     * @dev 提取收益（收益大于 50 USDC 允许随时提取）
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     */
    function _claimReward(bool _style) private {
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[_style][msg.sender];

        uint receiveReward;
        uint estimateReward = _calculateReward(_style);
        for (uint i = 0; i < orders.length; i++) {
            Order storage targetOrder = orders[i];
            if(estimateReward < 50e18 && targetOrder.endTime > block.timestamp) continue;
            uint time = Math.min(targetOrder.endTime, block.timestamp);
            receiveReward += (time - targetOrder.lastUpdateTime) / 1 days * _calculateRewardPerDay(_style, targetOrder.depositAmount);
            targetOrder.lastUpdateTime = block.timestamp;
            if(block.timestamp >= targetOrder.endTime) {
                targetOrder.withdrawReward = true;
            }
        }

        uint actualReceiveReward = receiveReward * 97 / 100;
        fees += receiveReward - actualReceiveReward;

        IERC20(USDC).transfer(msg.sender, actualReceiveReward);

        uint8 lockDays = _style ? 30 : 15;
        emit ClaimReward(msg.sender, actualReceiveReward, lockDays);
    }

    /**
     * @dev 计算用户的收益
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     */
    function _calculateReward(bool _style) view private returns (uint reward) {
        // 先获取用户对应的订单数组
        Order[] storage orders = userOrder[_style][msg.sender];
        
        for (uint i = 0; i < orders.length; i++) {
            Order memory targetOrder = orders[i];
            uint time = Math.min(targetOrder.endTime, block.timestamp);
            reward += (time - targetOrder.lastUpdateTime) / 1 days * _calculateRewardPerDay(_style, targetOrder.depositAmount);
        }
    }
    

    /**
     * @dev 计算每天的收益
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     * @param _depositAmount 质押数量
     */
    function _calculateRewardPerDay(bool _style, uint _depositAmount) view private returns (uint rewardPerDay) {
        (uint _totalDevices, uint _totalProfit_30days) = getDevicesAndProfit();    // gas saving
        uint8 lockDays = _style ? 30 : 15;
        rewardPerDay = _depositAmount / elecExpendPerDevice_30days * _totalProfit_30days / _totalDevices / 2 / lockDays;
    }

    // =========================================== 邀请返佣 ===========================================

    function checkReferralBonus() view public returns (uint referral_bonus) {
        referral_bonus = referralBonus[msg.sender];
    }

    function claimReferralBonus() external nonReentrant {
        uint referral_bonus = checkReferralBonus();
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

    function showFees() view public onlyOwner returns (uint) {
        return fees;
    }

    function redeemFees() external onlyOwner {
        uint fee_amount = showFees();
        delete fees;
        IERC20(USDC).transfer(msg.sender, fee_amount);

        emit RedeemFees(msg.sender, fee_amount);
    }
}