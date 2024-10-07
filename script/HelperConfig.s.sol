// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed; // WETH（以太坊）/USD 的价格预言机地址
        address wbtcUsdPriceFeed; // WBTC（比特币）/USD 的价格预言机地址
        address weth; // WETH 的代币地址
        address wbtc; // WBTC 的代币地址
        uint256 deployerKey; // 部署合约使用的私钥
    }

    uint8 public constant DECIMALS = 8; // 预言机价格返回的小数位数
    int256 public constant ETH_USD_PRICE = 2000e8; // 模拟的ETH/USD价格
    int256 public constant BTC_USD_PRICE = 1000e8; // 模拟的BTC/USD价格
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Anvil本地测试环境的默认私钥，用于本地开发时的部署者身份

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111){
            // 在 Sepolia 测试网上
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            // 默认使用本地的 Anvil 环境
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    // 获取Sepolia 网络上的实际 WETH 和 WBTC 的价格预言机地址和代币合约地址
    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        // 查询地址：https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY") // 从环境变量中获取部署者的私钥
        });
    }

    // 
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // 如果当前网络配置已经设置了wethUsdPriceFeed
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // 如果没有，则创建模拟的价格预言机MockV3Aggregator和代币ERC20Mock，
        // 分别用于ETH/USD和BTC/USD。
        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}