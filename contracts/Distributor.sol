// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Note that this pool has no minter key of BITI
// Instead, rewards will be sent to this pool at the beginning.
contract Distributor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. BITI to distribute per block.
        uint256 lastRewardBlock; // Last block number that BITI distribution occurs.
        uint256 accBitiPerShare; // Accumulated BITI per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
    }

    IERC20 public immutable biti;
    address public immutable controller;
    uint256 public accumulatedSoup;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The block number when BITI mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public runningBlocks = 10625000; // 368 days
    uint256 public constant TOTAL_REWARDS = 40000 ether;
    uint256 public bitiPerBlock = TOTAL_REWARDS / 10625000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _biti,
        address _controller,
        uint256 _startBlock
    ) {
        require(block.number < _startBlock, "late");
        biti = IERC20(_biti);
        controller = _controller;
        startBlock = _startBlock;
        endBlock = startBlock + runningBlocks;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Distributor: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "Distributor: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate,
        uint256 _lastRewardBlock
    ) public onlyOperator {
        checkPoolDuplicate(_lpToken);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.number < startBlock) {
            // chef is sleeping
            if (_lastRewardBlock == 0) {
                _lastRewardBlock = startBlock;
            } else {
                if (_lastRewardBlock < startBlock) {
                    _lastRewardBlock = startBlock;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardBlock == 0 || _lastRewardBlock < block.number) {
                _lastRewardBlock = block.number;
            }
        }
        bool _isStarted =
        (_lastRewardBlock <= startBlock) ||
        (_lastRewardBlock <= block.number);
        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : _lastRewardBlock,
            accBitiPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's BITI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from >= _to) return 0;
        if (_to >= endBlock) {
            if (_from >= endBlock) return 0;
            if (_from <= startBlock) return endBlock.sub(startBlock).mul(bitiPerBlock);
            return endBlock.sub(_from).mul(bitiPerBlock);
        } else {
            if (_to <= startBlock) return 0;
            if (_from <= startBlock) return _to.sub(startBlock).mul(bitiPerBlock);
            return _to.sub(_from).mul(bitiPerBlock);
        }
    }

    // View function to see pending BITI on frontend.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBitiPerShare = pool.accBitiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (_pid == 0) {
            // use accumulatedSoup instead
            lpSupply = accumulatedSoup;
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _bitiReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accBitiPerShare = accBitiPerShare.add(_bitiReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accBitiPerShare).div(1e18).sub(user.rewardDebt);
    }
    // View function to see user balance on frontend.
    function balanceOf(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (_pid == 0) {
            // use accumulatedReserves instead
            lpSupply = accumulatedSoup;
        }
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _bitiReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accBitiPerShare = pool.accBitiPerShare.add(_bitiReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accBitiPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeBitiTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            if (_pid == 0) {
                // send funds to controller instead
                pool.lpToken.safeTransferFrom(_sender, controller, _amount);
                user.amount = user.amount.add(_amount);
                accumulatedSoup += _amount;
            } else {
                pool.lpToken.safeTransferFrom(_sender, address(this), _amount);
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accBitiPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(_pid == 0, "withdraw: not allowed");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accBitiPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeBitiTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(_sender, _amount);
        } else {
            // withdraws all
            _amount = user.amount;
            user.amount = 0;
            pool.lpToken.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBitiPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require(_pid == 0, "emergencyWithdraw: not allowed");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe biti transfer function, just in case if rounding error causes pool to not have enough BITI.
    function safeBitiTransfer(address _to, uint256 _amount) internal {
        uint256 _bitiBal = biti.balanceOf(address(this));
        if (_bitiBal > 0) {
            if (_amount > _bitiBal) {
                biti.safeTransfer(_to, _bitiBal);
            } else {
                biti.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }
}
