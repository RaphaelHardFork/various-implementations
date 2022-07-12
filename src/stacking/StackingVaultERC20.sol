// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./IERC900.sol";

uint256 constant PRECISION = 10**40;

/**
 * @notice how are stored amounts
 * uint128 max = 340_282_366_920_938_500_000.0 Token
 * RBT without lose precision = 10_000_000_000_000_000_000.0 Token Stacked (50.0 rT | 10_000_000_000_000_000_000.0 sT | 10 years)
 * uint256 max = 115792089237316190000.0 x 10**57
 * max block = 18446744073694425000 block (enough)
 */

contract StackingVaultERC20 is IERC900, Ownable {
    /// @dev token distributed as rewards
    address public immutable override token;

    struct Timeline {
        // uint16 noRewardBlock
        uint64 startingBlock;
        uint64 lastDistributionBlock;
        uint64 lastBlockWithReward;
    }

    uint256 private _rewardPerTokenDistributed;

    /// @dev to save precision rewardPerBlockPerToken have +40 decimals
    uint256 private _currentRewardPerBlockPerToken;
    uint256 private _totalStaked;

    mapping(address => uint256) private _stackedAmount;
    mapping(address => uint256) private _rewardPerTokenPaid;
    Timeline private _timeline;

    event RewardPaid(address indexed account, uint256 amount);

    constructor(address rewardToken) {
        token = rewardToken;
    }

    modifier triggerDistribution() {
        _distribute();
        _;
    }

    /**
     * @dev when deposit the {_currentRewardPerBlockPerToken} increase and the last block is updated
     * */
    function deposit(uint256 amount, uint256 lastBlock)
        external
        onlyOwner
        triggerDistribution
    {
        require(
            lastBlock >= _timeline.lastBlockWithReward,
            "Stacking: shorter distribution"
        );

        // calculate number of block to the end
        uint256 remainingBlocks;
        if (_timeline.lastBlockWithReward > block.number) {
            remainingBlocks =
                uint256(_timeline.lastBlockWithReward) -
                block.number;
        }

        uint256 currentRBT = _currentRewardPerBlockPerToken;
        uint256 remainingAmount = (currentRBT *
            _totalStaked *
            remainingBlocks) / PRECISION;

        _currentRewardPerBlockPerToken =
            (((amount + remainingAmount) * PRECISION) / _totalStaked) *
            (lastBlock - block.number);

        require(_currentRewardPerBlockPerToken > 0, "Stacking: reward too low");
        require(
            _currentRewardPerBlockPerToken >= currentRBT,
            "Stacking: lower rewards"
        );

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _timeline.lastBlockWithReward = uint64(block.number);
    }

    function stake(uint256 amount, bytes calldata data) external {
        stakeFor(msg.sender, amount, data);
    }

    function stakeFor(
        address addr,
        uint256 amount,
        bytes calldata data
    ) public triggerDistribution {
        if (_totalStaked == 0) {
            _timeline.startingBlock = uint64(block.number);
        }

        _rewardPerTokenPaid[addr] = _rewardPerTokenDistributed;
        _stackedAmount[addr] += amount;
        _totalStaked += amount;

        IERC20(token).transferFrom(addr, address(this), amount);
        emit Staked(addr, amount, _totalStaked, data);
    }

    function unstake(uint256 amount, bytes calldata data) external {
        unstakeFor(msg.sender, amount, data);
    }

    function unstakeFor(
        address account,
        uint256 amount,
        bytes calldata data
    ) public triggerDistribution {
        _getReward(account);
        _stackedAmount[account] -= amount;
        _totalStaked -= amount;
        IERC20(token).transferFrom(address(this), account, amount);
        emit Unstaked(account, amount, _totalStaked, data);
    }

    function getReward(address account) external triggerDistribution {
        _getReward(account);
    }

    function totalStakedFor(address addr) external view returns (uint256) {
        return _stackedAmount[addr];
    }

    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    function supportsHistory() external pure returns (bool) {
        return false;
    }

    /**
     * @dev Update the last distribution block to the lastest block
     *      Add reward per token to distributed token per token
     * */
    function _distribute() internal {
        if (_currentRewardPerBlockPerToken > 0) {
            uint256 elapsedBlocks = block.number -
                uint256(_timeline.lastDistributionBlock);
            _rewardPerTokenDistributed +=
                elapsedBlocks *
                _currentRewardPerBlockPerToken;
            _timeline.lastDistributionBlock = uint64(block.number);
        }
    }

    /**
     * @dev {triggerDistribution} should be called before
     */
    function _getReward(address account) internal {
        uint256 rewards = ((_rewardPerTokenDistributed -
            _rewardPerTokenPaid[account]) * _stackedAmount[account]) /
            PRECISION;

        _rewardPerTokenPaid[account] = _rewardPerTokenDistributed;

        emit RewardPaid(account, rewards);
        IERC20(token).transferFrom(address(this), account, rewards);
    }
}
