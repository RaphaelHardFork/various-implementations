// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./IERC900.sol";

contract StakingVaultERC20 is IERC900, Ownable {
    uint256 public constant PRECISION = 10**40;

    /// @dev token distributed as rewards
    address public immutable override token;

    /// @dev token used for staking
    address public immutable stakedToken;

    struct Timeline {
        // uint16 noRewardBlock
        uint64 depositBlock;
        uint64 lastDistributionBlock;
        uint64 lastBlockWithReward;
    }

    /// @dev pool where users get their rewards
    uint256 private _rewardPerTokenDistributed;

    /// @dev reward/block/token is stored with +40 decimals to save accuracy
    uint256 private _currentRewardPerBlockPerToken;

    /// @dev total amount of token staked in the contract
    uint256 private _totalStaked;

    /// @dev used when owner deposit while no token are staked in the contract
    uint256 private _depositPool;

    /// @dev amount of staked token in the contract for one user
    mapping(address => uint256) private _stakedAmount;

    /// @dev amount of reward in the pool the user cannot benefit
    mapping(address => uint256) private _rewardPerTokenPaid;
    Timeline private _timeline;

    event RewardPaid(address indexed account, uint256 amount);

    event log(uint256 log);

    constructor(address rewardToken, address stakedToken_) {
        token = rewardToken;
        stakedToken = stakedToken_;
    }

    modifier triggerDistribution() {
        _distribute();
        _;
    }

    modifier triggerRewards(address account) {
        _getReward(account);
        _;
    }

    /**
     * @dev Deposit amount to distribute as reward, amount cannot be retrivied then.
     *      If there is no staked amount, checks are done with {_totalStacked == 1000 TOKEN} and the amount
     *      is stored in a temp_pool.
     * */
    function deposit(uint256 amount, uint256 lastBlock)
        external
        onlyOwner
        triggerDistribution
    {
        require(
            lastBlock >= _timeline.lastBlockWithReward,
            "Staking: shorter distribution"
        );
        require(lastBlock > block.number, "Staking: wrong end block");

        // transfer token
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // the amount is stored in {_depositPool} until the contract
        // have tokens staked.
        if (_totalStaked == 0) {
            if (_depositPool > 0) {
                lastBlock += block.number - _timeline.depositBlock;
            }
            _depositPool += amount;
            _validateRBT(
                _depositPool,
                1_000_000 * 10**18,
                lastBlock - block.number
            );

            _timeline.depositBlock = uint64(block.number);
            _timeline.lastBlockWithReward = uint64(lastBlock);
            return;
        }

        // active distribution if not started
        if (_currentRewardPerBlockPerToken == 0) {
            if (_depositPool > 0) {
                lastBlock += block.number - _timeline.depositBlock;
                amount += _depositPool;
                delete _depositPool;
            }
        }

        // add to current distribution and set it
        uint256 currentRBT = _currentRewardPerBlockPerToken;
        uint256 updatedRBT = _updateRBT(amount, lastBlock);
        require(updatedRBT >= currentRBT, "Staking: lower rewards");
    }

    function stake(uint256 amount, bytes calldata data) external {
        stakeFor(msg.sender, amount, data);
    }

    function stakeFor(
        address addr,
        uint256 amount,
        bytes calldata data
    ) public triggerDistribution triggerRewards(addr) {
        // update stake state
        _stakedAmount[addr] += amount;
        _totalStaked += amount;
        _rewardPerTokenPaid[addr] = _rewardPerTokenDistributed;
        IERC20(stakedToken).transferFrom(addr, address(this), amount);
        emit Staked(addr, amount, _totalStaked, data);

        uint256 rewardAmount;
        uint256 lastBlock = _timeline.lastBlockWithReward;

        if (_totalStaked - amount == 0) {
            if (_depositPool > 0) {
                // active distribution
                lastBlock += uint64(block.number) - _timeline.depositBlock;
                rewardAmount = _depositPool;
                delete _depositPool;
            } else {
                // stake without change distribution
                return;
            }
        }

        _updateRBT(rewardAmount, lastBlock);
    }

    function unstake(uint256 amount, bytes calldata data) external {
        unstakeFor(msg.sender, amount, data);
    }

    function unstakeFor(
        address account,
        uint256 amount,
        bytes calldata data
    ) public triggerDistribution triggerRewards(account) {
        _stakedAmount[account] -= amount;
        _totalStaked -= amount;
        IERC20(token).transferFrom(address(this), account, amount);
        emit Unstaked(account, amount, _totalStaked, data);

        // stop distribution
        if (_totalStaked == 0) {
            uint256 remainingBlocks = _timeline.lastBlockWithReward >
                block.number
                ? uint256(_timeline.lastBlockWithReward) - block.number
                : 0;
            uint256 remainingAmount = (_currentRewardPerBlockPerToken *
                remainingBlocks) / PRECISION;
            delete _currentRewardPerBlockPerToken;
            _depositPool = remainingAmount;
        }
    }

    function getReward(address account) external triggerDistribution {
        _getReward(account);
    }

    function totalStakedFor(address addr) external view returns (uint256) {
        return _stakedAmount[addr];
    }

    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    function currentReward() external view returns (uint256) {
        return _currentRewardPerBlockPerToken;
    }

    function depositPool() external view returns (uint256) {
        return _depositPool;
    }

    function timeline() external view returns (Timeline memory) {
        return _timeline;
    }

    function getAPR(int256 amount) external view returns (uint256) {
        // calculate RBT with new amount
    }

    function supportsHistory() external pure returns (bool) {
        return false;
    }

    /**
     * @dev Update the last distribution block to the lastest block
     *      Add reward per token to distributed token per token
     * */
    function _distribute() internal {
        if (uint256(_timeline.lastDistributionBlock) <= block.number) {
            uint256 elapsedBlocks = block.number -
                uint256(_timeline.lastDistributionBlock);
            _rewardPerTokenDistributed +=
                elapsedBlocks *
                _currentRewardPerBlockPerToken;
        }
        _timeline.lastDistributionBlock = uint64(block.number);
    }

    /**
     * @dev {triggerDistribution} should be called before
     */
    function _getReward(address account) internal {
        uint256 rewards = ((_rewardPerTokenDistributed -
            _rewardPerTokenPaid[account]) * _stakedAmount[account]) / PRECISION;

        _rewardPerTokenPaid[account] = _rewardPerTokenDistributed;

        if (rewards > 0) {
            emit RewardPaid(account, rewards);
            IERC20(token).transfer(account, rewards);
        }
    }

    function _validateRBT(
        uint256 amount,
        uint256 staked,
        uint256 duration
    ) internal pure returns (uint256 estimatedRBT) {
        estimatedRBT = (amount * PRECISION) / (staked * duration);
        require(estimatedRBT > 0, "Stacking: lower reward to zero");
    }

    /**
     * @dev Calculate the remaining amount to distribute (zero if distribution not started
     *      and if distribution is finished).
     *      Validate RBT and compare it to the previous (only for deposit)
     */
    function _updateRBT(uint256 amount, uint256 lastBlock)
        internal
        returns (uint256 updatedRBT)
    {
        uint256 remainingBlocks = _timeline.lastBlockWithReward > block.number
            ? uint256(_timeline.lastBlockWithReward) - block.number
            : 0;
        amount +=
            (_currentRewardPerBlockPerToken * _totalStaked * remainingBlocks) /
            PRECISION;
        updatedRBT = _validateRBT(
            amount,
            _totalStaked,
            lastBlock - block.number
        );
        _currentRewardPerBlockPerToken = updatedRBT;
        _timeline.lastBlockWithReward = uint64(lastBlock);
    }
}
