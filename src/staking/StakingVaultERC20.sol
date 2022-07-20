// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./IERC900.sol";

/**
 * @notice  This contract allow to distribute ERC20 reward block per block
 *          to users having a staked amount of another ERC20 token.
 *
 * @dev This contract implement the {IERC900} interface.
 *
 * This implementation is used for two distinct ERC20 (rewards and staked token),
 * if only one token is used, consider using an anti-compound number of block to avoid,
 * compound on each block.
 *
 * {Ownable} contract is used to restrict the {deposit} action to the `owner`, this ownership
 * can be renouced to allow users to add rewards. Anyway the amount of reward per block and per token staked,
 * cannot be lowered.
 *
 * As rewards are distributed each block, rewards are represented by {_currentRewardPerBlockPerToken},
 * which calculate amount of rewards to distribute to each token staked in the contract.
 *
 * NOTE This contract is not audited, use it with caution.
 *      Utilisation of the {IERC900} seem not to be so relevant.
 */

contract StakingVaultERC20 is IERC900, Ownable {
    uint256 public constant PRECISION = 10**40;

    /// @dev token distributed as rewards
    address public immutable override token;

    /// @dev token staked in the contract to get rewards
    address public immutable stakedToken;

    /// @dev store values associated with blocks
    struct Timeline {
        uint64 depositBlock;
        uint64 lastDistributionBlock;
        uint64 lastBlockWithReward;
    }

    /// @dev represents rewards distributed per token staked
    uint256 private _rewardPerTokenDistributed;

    /// @dev amount of rewards distributed each block (stored with +40 decimal)
    uint256 private _currentRewardPerBlockPerToken;

    /// @dev total amount of token staked in the contract
    uint256 private _totalStaked;

    /// @dev used to store rewards amount when no token are staked
    uint256 private _depositPool;

    /// @dev amount of token staked by an user
    mapping(address => uint256) private _stakedAmount;

    /// @dev amount of reward per token the user cannot benefit
    mapping(address => uint256) private _rewardPerTokenPaid;
    Timeline private _timeline;

    event RewardPaid(address indexed account, uint256 amount);

    /**
     * @dev Tokens address are `immutable`, considere using another contract
     * to change reward or staked token.
     *
     * @param rewardToken   token distributed as rewards
     * @param stakedToken_  token staked by users
     */
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
     * @dev Deposit `amount` of {rewardToken} into the contract for the distribution,
     *      This function is restricted to the `owner`.
     *
     *      The distribution start only if the amount staked in the contract is non-null,
     *      in this case the amount is stored in {_depositPool}. The distribution will start
     *      once an user stake an amount into the contract.
     *
     * Requirement:
     *      - `lastBlock` should be greater than actual block and the previous lastBlock
     *      - combinaison of `amount` & `lastBlock` should result a distribution over zero,
     *      and increase the actual distribution if the distribution is active.
     *
     * @param amount    amount of token to deposit into the contract
     * @param lastBlock last block where distribution will occurs
     * */
    function deposit(uint256 amount, uint256 lastBlock)
        external
        onlyOwner
        triggerDistribution
    {
        require(
            lastBlock >= _timeline.lastBlockWithReward &&
                lastBlock > block.number,
            "Staking: shorter distribution"
        );

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
        // this check is not performed when RBT = 0
        uint256 currentRBT = _currentRewardPerBlockPerToken;
        uint256 updatedRBT = _updateRBT(amount, lastBlock, 0);
        require(updatedRBT >= currentRBT, "Staking: lower rewards");
    }

    /**
     * @dev Stake an amount in the contract for the `sender`
     *
     * @param amount    amount of token to stake
     * @param data      _
     */
    function stake(uint256 amount, bytes calldata data) external override {
        stakeFor(msg.sender, amount, data);
    }

    /**
     * @dev Stake an amount in the contract for another address
     *
     * @param addr      address which will stake tokens
     * @param amount    amount of token to stake
     * @param data      _
     */
    function stakeFor(
        address addr,
        uint256 amount,
        bytes calldata data
    ) public override triggerDistribution triggerRewards(addr) {
        uint256 rewardAmount;
        uint256 lastBlock = _timeline.lastBlockWithReward;

        // update RBT only if active distribution
        // before update the stake amount
        if (_currentRewardPerBlockPerToken > 0) {
            _updateRBT(rewardAmount, lastBlock, int256(amount));
        } else if (_depositPool > 0) {
            // active distribution
            lastBlock += uint64(block.number) - _timeline.depositBlock;
            rewardAmount = _depositPool;
            delete _depositPool;
            _updateRBT(rewardAmount, lastBlock, int256(amount));
        }

        // update stake state
        _stakedAmount[addr] += amount;
        _totalStaked += amount;
        _rewardPerTokenPaid[addr] = _rewardPerTokenDistributed;
        IERC20(stakedToken).transferFrom(addr, address(this), amount);
        emit Staked(addr, amount, _totalStaked, data);
    }

    /**
     * @dev Unstake an amount in the contract for the `sender`
     *
     * @param amount    amount of token to unstake
     * @param data      _
     */
    function unstake(uint256 amount, bytes calldata data) external override {
        unstakeFor(msg.sender, amount, data);
    }

    /**
     * @dev Unstake an amount in the contract for another address
     *
     * @param account   address which will unstake tokens
     * @param amount    amount of token to unstake
     * @param data      _
     */
    function unstakeFor(
        address account,
        uint256 amount,
        bytes calldata data
    ) public triggerDistribution triggerRewards(account) {
        uint256 lastBlockWithReward = _timeline.lastBlockWithReward;
        // stop distribution if no more token in contract
        if (_totalStaked - amount == 0) {
            uint256 remainingBlocks = lastBlockWithReward > block.number
                ? uint256(lastBlockWithReward) - block.number
                : 0;
            uint256 remainingAmount = (_currentRewardPerBlockPerToken *
                remainingBlocks *
                _totalStaked) / PRECISION;
            delete _currentRewardPerBlockPerToken;
            if (remainingAmount > 0) {
                _depositPool = remainingAmount;
                _timeline.depositBlock = uint64(block.number);
            }
        } else {
            // update RBT only if dstribution active
            if (_currentRewardPerBlockPerToken > 0) {
                _updateRBT(0, lastBlockWithReward, int256(amount) * -1);
            }
        }

        // update stake state
        _stakedAmount[account] -= amount;
        _totalStaked -= amount;
        IERC20(stakedToken).transfer(account, amount);
        emit Unstaked(account, amount, _totalStaked, data);
    }

    function getReward(address account) external triggerDistribution {
        _getReward(account);
    }

    /**
     * @param addr  address to view balance of staked token
     * @return amount of token staked by an user
     */
    function totalStakedFor(address addr) external view returns (uint256) {
        return _stakedAmount[addr];
    }

    /**
     * @return total amount of token staked in the contract
     */
    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    /**
     * @return amount of reward distributed per block per token
     */
    function currentReward() external view returns (uint256) {
        return _currentRewardPerBlockPerToken;
    }

    /**
     * @return amount of rewards waiting for distribution
     */
    function depositPool() external view returns (uint256) {
        return _depositPool;
    }

    /**
     * @return information related to blocks
     *          - {depositBlock} block where an amount was deposited in {_depositPool}
     *          - {lastBlockWithReward} last block where distribution will occurs
     *          - {lastDistributionBlock} last block where rewards were added to {_rewardPerTokenDistributed}
     */
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
     *
     *      Should detect the end of distribution
     * */
    function _distribute() internal {
        uint256 currentBlock = block.number;
        uint256 lastBlockWithReward = _timeline.lastBlockWithReward;
        uint256 lastDistributionBlock = _timeline.lastDistributionBlock;

        // calculate reward until {lastBlockWithReward} maximum
        if (block.number > lastBlockWithReward && lastBlockWithReward != 0) {
            currentBlock = lastBlockWithReward;
        }

        // calculate only if the {lastBlockWithReward} is not reached
        if (
            currentBlock >= lastDistributionBlock &&
            _currentRewardPerBlockPerToken > 0
        ) {
            uint256 elapsedBlocks = currentBlock - lastDistributionBlock;
            _rewardPerTokenDistributed +=
                elapsedBlocks *
                _currentRewardPerBlockPerToken;

            // end of distribution
            if (lastBlockWithReward == currentBlock) {
                delete _currentRewardPerBlockPerToken;
            }
        }

        // update distribution block anyway
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
    function _updateRBT(
        uint256 amount,
        uint256 lastBlock,
        int256 totalStakedDelta
    ) internal returns (uint256 updatedRBT) {
        uint256 remainingBlocks = _timeline.lastBlockWithReward > block.number
            ? uint256(_timeline.lastBlockWithReward) - block.number
            : 0;
        amount +=
            (_currentRewardPerBlockPerToken * _totalStaked * remainingBlocks) /
            PRECISION;

        updatedRBT = _validateRBT(
            amount,
            uint256(int256(_totalStaked) + totalStakedDelta),
            block.number > lastBlock ? 0 : lastBlock - block.number
        );
        _currentRewardPerBlockPerToken = updatedRBT;
        _timeline.lastBlockWithReward = uint64(lastBlock);
    }
}
