// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../BasicERC20.sol";
import "../stacking/Distribute.sol";

contract Distribute_test is DSTest, Test {
    address public constant OWNER = address(777);
    address public constant USER1 = address(1);
    address public constant USER2 = address(2);
    uint256 public constant MAX_STAKE = 100_000_000_000_000 * 10**18;

    BasicERC20 public token; // is decimal 18
    Distribute public distribute;

    function setUp() public {
        vm.startPrank(OWNER);
        token = new BasicERC20();
        distribute = new Distribute(18, token);
    }

    function testDeployment() public {
        assertEq(distribute.bond_value(), 1000000);
        assertEq(distribute.investor_count(), 0);
        assertEq(distribute.to_distribute(), 0);
        assertEq(address(distribute.reward_token()), address(token));
    }

    // ---------------------------- stakeFor()
    function testCannotStakeForZeroAddr(uint256 amount) public {
        vm.assume(amount > 0);
        vm.expectRevert(bytes("Distribute: Invalid account"));
        distribute.stakeFor(address(0), amount);
    }

    function testCannotStakeForNothing() public {
        vm.expectRevert(bytes("Distribute: Amount must be greater than zero"));
        distribute.stakeFor(USER1, 0);
    }

    function testStakeFor(uint256 amount) public {
        vm.assume(amount <= MAX_STAKE && amount > 0);
        distribute.stakeFor(USER1, amount);

        assertEq(distribute.totalStaked(), amount);
        assertEq(distribute.investor_count(), 1);
        assertEq(distribute.totalStakedFor(USER1), amount);
        assertEq(distribute.getReward(USER1), 0);
    }

    function testStakeForTwoTime(uint256 amount) public {
        vm.assume(amount <= MAX_STAKE && amount > 4);
        distribute.stakeFor(USER1, amount / 2);
        distribute.stakeFor(USER1, amount / 2);

        assertApproxEqAbs(distribute.totalStaked(), amount, 1);
        assertEq(distribute.investor_count(), 1);
        assertApproxEqAbs(distribute.totalStakedFor(USER1), amount, 1);
        assertEq(distribute.getReward(USER1), 0);
    }

    function testStakeForWithUser2(uint256 amount) public {
        vm.assume(amount <= MAX_STAKE && amount > 4);
        distribute.stakeFor(USER1, amount);
        distribute.stakeFor(USER2, amount);

        assertEq(distribute.totalStaked(), amount * 2);
        assertEq(distribute.investor_count(), 2);
        assertEq(distribute.totalStakedFor(USER2), amount);
        assertEq(distribute.getReward(USER2), 0);
    }

    // ---------------------------- unstakeFrom()
    function testCannotUnstakeFrom(uint256 amount) public {
        vm.assume(amount > 0);
        vm.expectRevert(bytes("Distribute: Invalid account"));
        distribute.unstakeFrom(payable(address(0)), amount);

        vm.expectRevert(bytes("Distribute: Amount must be greater than zero"));
        distribute.unstakeFrom(payable(USER1), 0);

        vm.assume(amount <= MAX_STAKE && amount > 10);
        distribute.stakeFor(USER1, amount);
        vm.expectRevert(bytes("Distribute: Dont have enough staked"));
        distribute.unstakeFrom(payable(USER1), amount + 100);
    }

    function testUnstakeFromPartial(uint256 amount) public {
        vm.assume(amount <= MAX_STAKE && amount > 10);
        distribute.stakeFor(USER1, amount);
        distribute.unstakeFrom(payable(USER1), amount / 2);

        assertApproxEqAbs(distribute.totalStaked(), amount / 2, 1);
        assertEq(distribute.investor_count(), 1);
        assertApproxEqAbs(distribute.totalStakedFor(USER1), amount / 2, 1);
    }

    function testUnstakeFromTotal(uint256 amount) public {
        vm.assume(amount <= MAX_STAKE && amount > 10);
        distribute.stakeFor(USER1, amount);
        distribute.unstakeFrom(payable(USER1), amount);

        assertApproxEqAbs(distribute.totalStaked(), 0, 1);
        assertEq(distribute.investor_count(), 0);
        assertApproxEqAbs(distribute.totalStakedFor(USER1), 0, 1);
    }

    // ---------------------------- distribute()
    function beforeDistribute(uint256 amount) internal {
        vm.assume(amount > 0 && amount < MAX_STAKE);
        vm.stopPrank();
        vm.startPrank(OWNER);
        token.mint(OWNER, amount);
        token.approve(address(distribute), amount);
    }

    function usersStake() internal {
        distribute.stakeFor(USER1, 100_000 * 10**18);
        distribute.stakeFor(USER2, 100_000 * 10**18);
    }

    function testDistributeWithNoStake(uint256 amount) public {
        beforeDistribute(amount);

        distribute.distribute(amount, OWNER);
        assertEq(distribute.bond_value(), 1000000);
    }

    function testDistributeWithStake(uint256 amount) public {
        beforeDistribute(amount);
        emit log_uint(distribute.bond_value());
        usersStake();

        emit log_uint(distribute.bond_value());

        distribute.stakeFor(USER1, 1000 * 10**18);
        emit log_uint(distribute.bond_value());
        distribute.distribute(amount, OWNER);
        emit log_uint(distribute.bond_value());
        uint256 userReward = distribute.getReward(USER1);
        distribute.stakeFor(USER1, 1);
        emit log_uint(distribute.bond_value());
        uint256 userReward2 = distribute.getReward(USER1);

        assertEq(userReward, userReward2);
    }
}
