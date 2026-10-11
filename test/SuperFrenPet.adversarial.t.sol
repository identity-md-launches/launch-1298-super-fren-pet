// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "src/SuperFrenPet.sol";

/// @dev Adds boundary and multi-call properties to the original deployment/ERC-20 suite.
/// forge-config: default.fuzz.runs = 1024
contract SuperFrenPetAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SuperFrenPet private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new SuperFrenPet();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_OneBaseUnitCanBeSpentOnlyOnce() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);

        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(0, 1, SUPPLY - 1);
    }

    function test_MaxUintTransferCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        _assertBalances(0, 0, SUPPLY);
    }

    function test_MaxUintAllowanceCannotCreateTokensOrBypassBalanceCheck() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0, SUPPLY);
    }

    function test_MaxUintMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        _assertBalances(1, SUPPLY - 1, 0);
    }

    function test_OwnerUsingTransferFromStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        _assertBalances(0, 0, SUPPLY);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(1, 0, SUPPLY - 1);
    }

    function test_UnlimitedAllowanceCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(2, 0, SUPPLY - 2);
    }

    function test_IndependentSpendersCannotSpendTheSameBalanceTwice() public {
        assertTrue(token.transfer(alice, 2));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 2));
        assertTrue(token.approve(bob, 2));
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 2));
        vm.prank(bob);
        token.transferFrom(alice, bob, 2);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), 2);
        _assertBalances(0, 2, SUPPLY - 2);

        // The failed call must leave Bob's authorization usable after Alice is funded again.
        vm.prank(bob);
        assertTrue(token.transfer(alice, 2));
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(0, 2, SUPPLY - 2);
    }

    function test_FailedSelfTransferFromPreservesBalanceAndAllowance() public {
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        _assertBalances(0, 0, SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(0, 0, SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertBalances(0, 0, SUPPLY);
    }

    function testFuzz_InsufficientAllowanceLeavesAllFundsAndApprovalIntact(
        uint256 held,
        uint256 approved,
        uint256 amount
    ) public {
        held = bound(held, 1, SUPPLY);
        approved = bound(approved, 0, held - 1);
        amount = bound(amount, approved + 1, held);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        // The balance is sufficient: this specifically exercises the allowance failure.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(held, 0, SUPPLY - held);
    }

    function testFuzz_InsufficientBalanceDoesNotConsumeFiniteAllowance(uint256 held, uint256 approved, uint256 amount)
        public
    {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max - 1);
        approved = bound(approved, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(held, 0, SUPPLY - held);
    }

    function testFuzz_InvalidRecipientDoesNotConsumeAllowance(uint256 amount, uint256 approved, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        approved = unlimited ? type(uint256).max : bound(approved, amount, type(uint256).max - 1);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(0, 0, SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsExactAndIdempotent(uint256 first, uint256 replacement) public {
        assertTrue(token.approve(spender, first));
        assertEq(token.allowance(address(this), spender), first);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        _assertBalances(0, 0, SUPPLY);
    }

    function testFuzz_SelfTransferFromOnlyConsumesFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        _assertBalances(0, 0, SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersEqualOneTransfer(uint256 first, uint256 second, uint256 approved) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        approved = bound(approved, first + second, type(uint256).max);
        SuperFrenPet aggregateToken = new SuperFrenPet();
        assertTrue(token.approve(spender, approved));
        assertTrue(aggregateToken.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, second));
        assertTrue(aggregateToken.transferFrom(address(this), alice, first + second));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), aggregateToken.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), aggregateToken.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), aggregateToken.allowance(address(this), spender));
        assertEq(aggregateToken.totalSupply(), SUPPLY);
        _assertBalances(first + second, 0, SUPPLY - first - second);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance, uint256 deployerBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance, "Alice's balance");
        assertEq(token.balanceOf(bob), bobBalance, "Bob's balance");
        assertEq(token.balanceOf(address(this)), deployerBalance, "deployer's balance");
        assertEq(token.balanceOf(spender), 0, "spender must not gain tokens");
        assertEq(token.balanceOf(address(0)), 0, "zero address must not gain tokens");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply");
    }
}
