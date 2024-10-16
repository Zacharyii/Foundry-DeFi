// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol"; // 使用ReentrancyGuard来防止重入攻击，确保安全性
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved(); //在清算后健康因子没有改善

    /////////////////  状态变量 /////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 预言机返回的价格一般是8位小数，所以要乘以1e10来增加精度。
    uint256 private constant PRECISION = 1e18; // 以太坊的标准精度，乘以它，将比率计算转化为整数计算。
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 清算门槛是50%，即允许使用50%的抵押品价值来借贷。
    uint256 private constant LIQUIDATION_PRECISION = 100; // 用来和门槛进行计算时保持一致的精度，通常设置为100。
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 最小健康因子
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; // 存储每个代币地址及其对应的价格馈送地址
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //每个用户存入的抵押品数量
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    // 不可变的DSC合约实例，用于铸造和管理DSC。
    DecentralizedStableCoin private immutable i_dsc;

    /////////////////  事件 /////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

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
    /*
     * @param tokenCollateralAddress 作为抵押物的代币地址
     * @param amountCollateral 存入的抵押物数量
     * @param amountDscToMint 要铸造的DSC数量
     * @notice 用于存入抵押物和铸造DSC
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscMint);
    }

    /*
     * @notice 遵循CEI模式（Checks(检查),Effects(效果),Interactions(交互)）
     * @param tokenCollateralAddress 抵押品存入的代币地址
     * @param amountCollateral 存入的抵押品数量
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /*
     * @param tokenCollateralAddress 要赎回的抵押物地址
     * @param amountCollateral 赎回数量
     * @param amountDscToBurn 销毁的DSC数量
     * @notice 销毁DSC和赎回抵押物
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn); //销毁DSC
        redeemCollateral(tokenCollateralAddress, amountCollateral); //赎回抵押物
    }

    // 赎回抵押品，赎回后健康因子必须大于1
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        //进行抵押品的实际赎回，msg.sender 既是赎回的发起者，也是接受者
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        //检查赎回后用户的健康因子是否仍然有效
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice 遵从CEI
     * @param amountDscToMint 要铸造的去中心化稳定币的数量
     * @notice 抵押品价值必须超过最低门槛
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        //销毁DSC代币
        _burnDsc(amount, msg.sender, msg.sender);
        //检查用户的健康因子是否被破坏
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /* 
     * @param collateral：用户用于抵押的ERC20代币的地址。
     * @param user：被清算的用户地址。其健康因子低于预设值，说明该用户资不抵债。
     * @param debtToCover：清算者希望销毁的DSC数量，用以覆盖用户的部分债务。
     * @notice 当用户的健康因子（抵押品价值与债务的比率）低于设定的最小值时，清算该用户并给予清算者奖励。
     * @notice 清算者可以销毁一定数量的DSC来清算用户部分或全部的抵押品。
     * @notice 清算者将获得清算奖励，奖励额为用户被清算的抵押品价值的10%。
     * @notice 一个已知的问题是，如果协议的抵押率低于或等于100%，我们将无法激励清算者
     * 例如，如果抵押品的价格在清算之前暴跌，我们将无法及时清算用户
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //获取用户的健康因子，检查是否需要清算
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //将美元债务（debtToCover）转换为用户抵押的代币数量
        //根据抵押品的当前价格，清算者需要销毁一定数量的DSC，来获得相应价值的抵押品。
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //清算奖励
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        //清算者可以赎回的总抵押品数量，等于债务对应的抵押品数量加上清算奖励。
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        //检查清算后用户的健康因子，确保已改善，如果没有则抛出错误
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////  private & internal view 函数 /////////////////
    /*
     * @param amountDscToBurn：要销毁的DSC数量
     * @param onBehalfOf：销毁的发起者
     * @param dscFrom：转移DSC的地址
     * @dev 底层internal函数，请勿调用，除非是检查健康因子被破坏的情况
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // 从用户的已铸造DSC数量中减去要销毁的数量
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        // 转移DSC到合约地址并销毁
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        // 从用户的已存抵押品中减去赎回的数量
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // 将抵押品转移到接受者，如果转移失败则抛出错误
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    }

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

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
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

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /////////////////  public & external view 函数 /////////////////
    // 将美元债务（以Wei为单位）转换为用户抵押的代币数量。
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //s_priceFeeds[token] 是存储每种代币的价格预言机地址的映射。
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //priceFeed.latestRoundData() 获取该代币的最新价格。
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // 遍历每个抵押物代币，获取他们存入的数量，并映射到价格，以计算出美元价值
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    // 将用户的抵押品转换成美元价值
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
