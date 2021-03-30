// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "./library/utils/SafeMath.sol";
import "./library/ERC20.sol";
import "./library/Operator.sol";
import "./library/utils/Address.sol";
import "./library/IBitiToken.sol";

/**
 * @title Biti
 * Biti - a contract for Biti tokens
 */
contract Biti is ERC20, Operator, IBitiToken {
    using SafeMath for uint256;
    using Address for address;

    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 60000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 2000 ether; // 5%

    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime = 1617163200; // Wednesday, March 31, 2021 4:00:00 AM
    uint256 public endTime = startTime + VESTING_DURATION;

    uint256 public devFundRewardRate = DEV_FUND_POOL_ALLOCATION / VESTING_DURATION;
    address public devFund;
    uint256 public devFundLastClaimed = startTime;
    bool public rewardPoolDistributed = false;

    constructor() ERC20("biti city", "BITI") {
        _mint(msg.sender, 1 ether); // mint 1 BITI for initial pools deployment
        devFund = msg.sender;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    /**
     * @notice Must only be called by the game operator
     */
    function mint(address _to, uint256 _amount) external onlyOperator override {
        _mint(_to, _amount);
        uint256 devMint = _amount.mul(5).div(100); // 5%
        _mint(devFund, devMint);
    }
}
