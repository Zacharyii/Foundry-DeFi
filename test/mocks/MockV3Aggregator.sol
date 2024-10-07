// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockV3Aggregator
 * @notice Based on the FluxAggregator contract
 * @notice Use this contract when you need to test
 * other contract's ability to read data from an
 * aggregator contract, but how the aggregator got
 * its answer is unimportant
 *
 * 用于测试与价格预言机交互的智能合约。
 * MockV3Aggregator 模拟了实际的 Chainlink 预言机，
 * 允许开发者在本地或测试环境中手动设置价格数据，而不依赖真实的价格来源。
 */
contract MockV3Aggregator {
    uint256 public constant version = 0; //定义了合约的版本号

    uint8 public decimals; // 价格的精度
    int256 public latestAnswer; // 最新的价格数据
    uint256 public latestTimestamp; // 最新的价格更新时的时间戳
    uint256 public latestRound; // 最新的价格更新轮次

    mapping(uint256 => int256) public getAnswer; // 存储每一轮的价格
    mapping(uint256 => uint256) public getTimestamp; // 存储每一轮的时间戳
    mapping(uint256 => uint256) private getStartedAt; // 存储每轮价格开始的时间

    // 部署合约时，设置精度和初始价格
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    // 手动更新价格、时间戳、轮次
    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    // 手动更新价格、开始时间、更新时间和轮次编号
    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = _timestamp;
        getStartedAt[latestRound] = _startedAt;
    }

    // 返回最新轮次的价格、开始时间、更新时间和轮次编号
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId);
    }

    // 返回最新轮次的价格、开始时间、更新时间和轮次编号
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            uint80(latestRound)
        );
    }

    // 返回合约的描述
    function description() external pure returns (string memory) {
        return "v0.6/tests/MockV3Aggregator.sol";
    }
}