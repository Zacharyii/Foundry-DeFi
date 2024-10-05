// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // 使用ReentrancyGuard来防止重入攻击，确保安全性
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    /////////////////  状态变量 /////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 预言机返回的价格一般是8位小数，所以要乘以1e10来增加精度。
    uint256 private constant PRECISION = 1e18; // 以太坊的标准精度，乘以它，将比率计算转化为整数计算。
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 清算门槛是50%，即允许使用50%的抵押品价值来借贷。
    uint256 private constant LIQUIDATION_PRECISION = 100; // 用来和门槛进行计算时保持一致的精度，通常设置为100。
    uint256 private constant MIN_HEALTH_FACTOR = 1; // 最小健康因子

    mapping(address token => address priceFeed) private s_priceFeeds; // 存储每个代币地址及其对应的价格馈送地址
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //每个用户存入的抵押品数量
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    // 不可变的DSC合约实例，用于铸造和管理DSC。
    DecentralizedStableCoin private immutable i_dsc;

    /////////////////  事件 /////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /////////////////  修饰符 /////////////////
    // 确保传入的amount大于零。
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
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
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // 初始化DSC合约实例i_dsc
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////  external 函数 /////////////////
    function depositCollateralAndMintDsc() external {}

    /*
     * @notice 遵循CEI模式（Checks(检查),Effects(效果),Interactions(交互)）
     * @param tokenCollateralAddress 抵押品存入的代币地址
     * @param amountCollateral 存入的抵押品数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // 更新用户在指定代币上的存入金额
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
     * @notice 遵从CEI
     * @param amountDscToMint 要铸造的去中心化稳定币的数量
     * @notice 抵押品价值必须超过最低门槛
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////  private & internal view 函数 /////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // totalDscMinted：用户已经铸造的DSC数量（即用户从系统借出的稳定币总量）
        // collateralValueInUsd：用户存入的抵押品总价值（以美元计）
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // LIQUIDATION_THRESHOLD：清算门槛,代表可以用于借贷的抵押品价值百分比。
        // collateralAdjustedForThreshold：根据清算门槛调整用户的抵押品价值，这里(*LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION相当于乘50%。
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////  public & external view 函数 /////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // 遍历每个抵押物代币，获取他们存入的数量，并映射到价格，以计算出美元价值
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    // 将用户的抵押品转换成美元价值
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // priceFeed：从Chainlink预言机获取某个代币的最新美元价格
        // price：预言机返回的价格是一个带有 8 位小数的整数
        // amount：用户存入的代币数量
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 如果存入1ETH，1ETH = $1000，则从CL的返回值是 1000 * 1e8
        // PRECISION 用来调整结果的精度，保持计算结果是以 18 位精度表示
        // 最终的美元价值 = (1000 * 1e10 * 1) / 1e18 = 1000 USD
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; 
    }
}
