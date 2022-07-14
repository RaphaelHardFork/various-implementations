// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../BasicERC20.sol";
import "../staking/StakingVaultERC20.sol";

contract StakingVaultERC20_test is DSTest, Test {
    // CONSTANT
    address public constant OWNER = address(501);
    address public constant USER1 = address(1);
    address public constant USER2 = address(2);
    uint256 public constant D18 = 10**18;
    uint256 public constant MONTH = 4096 * 30;

    // CONTRACT
    BasicERC20 public token;
    BasicERC20 public rewards;
    StakingVaultERC20 public staking;

    function setUp() public {
        vm.roll(1000);
        vm.startPrank(OWNER);
        token = new BasicERC20();
        rewards = new BasicERC20();
        staking = new StakingVaultERC20(address(rewards), address(token));
        vm.stopPrank();
    }

    // --- before distribution start ---
    function testStake(uint256 amount) public {
        _userStake(USER1, amount);

        assertEq(token.balanceOf(address(staking)), amount);
        assertEq(staking.totalStakedFor(USER1), amount);
        assertEq(staking.totalStaked(), amount);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
    }

    function testDeposit(uint256 amount) public {
        _deposit(amount, 10000);

        assertEq(rewards.balanceOf(address(staking)), amount);
        assertEq(staking.timeline().lastBlockWithReward, 10000);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), amount);
    }

    // --- active distribution ---
    function testActiveWithDeposit() public {
        uint256 amount = 20000 * D18;
        _userStake(USER1, amount);
        vm.roll(2000);
        _deposit(amount * 2, 30000);

        assertEq(staking.timeline().lastBlockWithReward, 30000);
        assertEq(staking.timeline().lastDistributionBlock, 2000);
        assertEq(
            staking.currentReward(),
            _calculRBT(amount * 2, 30000 - 2000, amount)
        );
    }

    function testActiveWithStake() public {
        uint256 amount = 30000 * D18;
        _deposit(amount, 30000);
        vm.roll(2000);
        _userStake(USER1, amount * 2);

        assertEq(staking.timeline().lastBlockWithReward, 30000);
        assertEq(staking.timeline().lastDistributionBlock, 2000);
        assertEq(
            staking.currentReward(),
            _calculRBT(amount, 30000 - 2000, amount * 2)
        );
    }

    // --- get rewards ---
    function testGetReward() public {
        uint256 amount = 30000 * D18;
        _deposit(amount, 30000);
        vm.roll(2000);
        _userStake(USER1, amount * 2);

        vm.roll(30000);
        vm.startPrank(USER1);
        staking.getReward(USER1);

        assertApproxEqAbs(rewards.balanceOf(USER1), amount, 100);
        assertApproxEqAbs(rewards.balanceOf(address(staking)), 0, 100);
    }

    // --- fuzz testing ---
    // function _contextStaking(
    //     uint256 rewardAmount,
    //     uint256 amountStaked,
    //     uint64 lastBlock,
    //     uint8 nbOfUser
    // ) internal {
    //     // rewards deposited
    //     _deposit(rewardAmount, lastBlock);

    //     // random user stake
    //     for (uint256 i; i < nbOfUser; ) {
    //         vm.roll(1000 + i * 1000);
    //         _mintTo(
    //             address(uint160(nbOfUser)),
    //             (((amountStaked * amountStaked * i))) % (50000 * D18)
    //         );
    //         _userStake(
    //             address(uint160(nbOfUser)),
    //             amountStaked * amountStaked * i
    //         );
    //     }
    // }

    // +-----------------------------------------------------+
    // |                        UTILS                        |
    // +-----------------------------------------------------+
    function _userStake(address user, uint256 amount) internal {
        _mintTo(token, user, amount);
        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount, "");
        vm.stopPrank();
    }

    function _deposit(uint256 amount, uint64 lastBlock) internal {
        vm.assume(amount > 0);
        _mintTo(rewards, OWNER, amount);
        vm.startPrank(OWNER);
        rewards.approve(address(staking), amount);
        staking.deposit(amount, lastBlock);
        vm.stopPrank();
    }

    function _mintTo(
        BasicERC20 _token,
        address account,
        uint256 amount
    ) internal {
        vm.assume(amount < 500_000_000_000_000 * D18);
        vm.prank(OWNER);
        _token.mint(account, amount);
    }

    function _calculRBT(
        uint256 amount,
        uint256 blockRange,
        uint256 totalStaked
    ) internal pure returns (uint256) {
        return (amount * 10**40) / (blockRange * totalStaked);
    }

    function _calculReward() internal view {
        //
    }
}
