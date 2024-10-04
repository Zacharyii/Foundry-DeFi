// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
// 使用ReentrancyGuard来防止重入攻击，确保安全性
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
 * @Author: 晨老斯
 * @Description: 此合约是去中心化稳定币系统的核心。
 * 它处理铸造和赎回DSC的所有逻辑，以及存入和提取抵押品。
 *
 * @notice 本项目保持1代币==1美元的锚定。
 * 本稳定币具有以下特性：
 * - 外部抵押
 * - 美元锚定
 * - 算法稳定
 *
 * 如果DAI没有治理、没有费用，并且仅由WETH和WBTC支持，那么它与DAI相似。
 *
 * 本DSC系统应始终保持超额抵押。
 * 在任何时候，所有抵押品的价值都不应低于所有DSC的美元支持价值。
 *
 * @notice 此合约基于MakerDAO DSS系统
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////   错误定义   /////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();

    /////////////////  状态变量 /////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // 存储每个代币地址及其对应的价格馈送地址
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //每个用户存入的抵押品数量

    // 不可变的DSC合约实例，用于铸造和管理DSC。
    DecentralizedStableCoin private immutable i_dsc;

    /////////////////  修饰符 /////////////////
    // 确保传入的amount大于零。
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // 检查传入的代币地址是否在允许的代币列表中。
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////  构造函数 /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC /USD, MKR / USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        // 初始化DSC合约实例i_dsc
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////  外部函数 /////////////////
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // 更新用户在指定代币上的存入金额
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
