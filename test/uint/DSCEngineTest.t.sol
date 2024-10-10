// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer; //用于部署 DSC 和 DSCEngine 的 DeployDSC 实例
    DecentralizedStableCoin dsc; //已部署的 DecentralizedStableCoin 实例
    DSCEngine dsce; //已部署的 DSCEngine 实例
    HelperConfig config; //用于获取价格预言机和 WETH 地址
    address ethUsdPriceFeed; //ETH/USD 的价格预言机地址
    address btcUsdPriceFeed; //BTC/USD 的价格预言机地址
    address weth; //WETH 代币的地址

    address public USER = makeAddr("user"); //用于模拟测试环境中的用户地址
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; //用户提供的抵押物数量
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; //账户初始ERC20代币余额

    function setUp() public {
        deployer = new DeployDSC(); // 实例化部署者
        (dsc, dsce, config) = deployer.run(); // 部署 DSC、DSCEngine，并获取配置
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig(); // 获取 WETH 地址和价格预言机

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE); // 为用户铸造初始的 WETH 代币
    }

    //////////////////Constructor tests////////////////////
    address[] public tokenAddresses;//存储抵押代币（如 WETH）的地址
    address[] public priceFeedAddresses;//存储与代币相关的预言机地址

    //测试代币地址和价格预言机地址的数组长度不匹配
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        //模拟预期的回退错误
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        //尝试创建 DSCEngine 实例，由于长度不匹配，合约会回退
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //测试 getTokenAmountFromUsd 函数，它将给定的美元金额转换为相应的代币数量
    function testGetTokenAmountFromUsd() public {
        //美元金额 usdAmount(100 ether)，表示100美元
        uint256 usdAmount = 100 ether;
        //假设当前价格是 2000 美元/ETH，期望的 WETH 数量为 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        // 获取实际的 WETH 数量，并使用 assertEq 验证与期望结果一致
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //////////////////price tests////////////////////
    // 检查 DSCEngine 合约的 getUsdValue 函数是否正确计算出 WETH 的美元价值
    function testGetUsdValue() public {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsd = 30000e18; // 预期的 USD 值（30000 USD）
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount); // 调用 DSCEngine 获取实际 USD 值
        assertEq(expectedUsd, actualUsd); // 断言预期值和实际值是否相等
    }

    //////////////////depositColleteral tests////////////////////
    // 检查如果用户尝试存入 0 作为抵押品，DSCEngine 是否会正确地回退交易
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER); // 以用户身份开始交易
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // 用户批准将 WETH 抵押到 DSCEngine

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector); // 预期交易会失败，并且失败原因是 'NeedsMoreThanZero'
        dsce.depositCollateral(weth, 0); // 尝试存入 0 WETH 作为抵押品，应该失败
        vm.stopPrank(); // 停止用户身份
    }

    //测试未批准的抵押品会导致回退
    function testRevertsWithUnapprovedCollateral() public {
        //创建一个模拟的ERC20代币 ranToken
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        //模拟 USER 调用该函数
        vm.startPrank(USER);
        //预期回退错误 DSCEngine__NotAllowedToken，表示该代币不被允许作为抵押品
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        //尝试存入该代币
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //测试执行前用户已经存入了一定的 WETH 抵押品
    modifier depositedCollateral() {
        vm.startPrank(USER);
        //用户首先批准合约可以花费一定数量的 WETH
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        //存入抵押品
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    //测试用户存入抵押品后，能否正确获取账户信息，包括抵押品的价值和铸造的DSC数量
    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;

        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
