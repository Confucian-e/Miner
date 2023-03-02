// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Miner is Ownable, ReentrancyGuard {
    // BSC 链 USDC 地址，精度为 18
    address constant public USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    uint constant elecExpendPerDevice_30days = 1.2195e20;   // 121.95 USDC

    // 用户邀请返佣奖励
    mapping (address => uint) referralBonus;

    // 用户质押的总数。区分 15/30，false 代表 15，true 代表 30
    mapping (bool => mapping (address => uint)) userTotalDepositAmount;

    // 用户质押的单数
    mapping (bool => mapping (address => uint8)) userTotalDepositOrders;

    // 矿场总矿机台数 Y
    uint private totalDevices;
    // 矿场 30 天总收益 Z
    uint private totalProfit_30days;

    // 积累的手续费
    uint private fees;

    struct Order {
        uint depositAmount;
        uint lastUpdateTime;
        uint endTime;
        bool open;
    }

    // 15/30 => 用户 => 用户的订单数组
    mapping (bool => mapping (address => Order[])) userOrder;

    event Deposit(address indexed user, uint amount, uint8 lockDays);
    event Withdraw(address indexed user, uint amount, uint8 lockDays);


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
        Order storage newOrder = Order(
            _depositAmount,
            block.timestamp,
            block.timestamp + lockDays * 1 days,
            true
        );

        // 将新的订单加入对应数组
        orders.push(newOrder);

        userTotalDepositOrders[_style][msg.sender]++;                       // 质押总订单数 +1
        userTotalDepositAmount[_style][msg.sender] += _depositAmount;      // 质押总数 + 新的质押数

        if(_invitation != address(0)) referralBonus[_invitation] += _depositAmount / 100;   // 邀请人奖励，1%

        emit Deposit(msg.sender, _depositAmount, lockDays);
    }


    /**
     * @dev 提取本金
     * @param _style 矿机类型，false 代表 15 天，true 代表 30 天
     */
    function _withdraw(bool _style) private nonReentrant {
        // 先获取用户对应的订单数组
        Order[] orders = userOrder[_style][msg.sender];

        uint8 len = userTotalDepositOrders[_style][msg.sender];

        uint receiveAmount;
        for (uint i = 0; i < len; i++) {
            Order memory targetOrder = orders[i];
            if(targetOrder.endTime <= block.timestamp && targetOrder.open) {
                receiveAmount += targetOrder.depositAmount;
                targetOrder.open = false;
            }
            if(targetOrder.endTime > block.timestamp) break;
        }
        uint actualReceiveAmount = receiveAmount * 97 / 100;
        fees += receiveAmount - actualReceiveAmount;

        IERC20(USDC).transfer(msg.sender, actualReceiveAmount);

        uint8 lockDays = _style ? 30 : 15;
        emit Withdraw(msg.sender, actualReceiveAmount, lockDays);
    }


    


    /**
     * @dev 管理员设置 
     * @param _totalDevices 矿场总矿机台数 Y
     * @param _totalProfit_30days 矿场 30 天总收益 Z
     */ 
    function setDevicesAndProfit(uint _totalDevices, uint _totalProfit_30days) external onlyOwner {
        totalDevices = _totalDevices;
        totalProfit_30days = _totalProfit_30days;
    }

    function _getDevicesAndProfit() private returns (uint _totalDevices, uint _totalProfit_30days) {
        _totalDevices = totalDevices;
        _totalProfit_30days = totalProfit_30days;
    }
}