// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "../src/SuperFrenPet.sol";

/// @dev All token movements stay within four holders, so their balances account for the whole supply.
/// Expected failures leave the model untouched; the invariant checks rollback after every action.
contract TokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SuperFrenPet public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SuperFrenPet token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from];
        amount = bound(amount, 0, available < approved ? available : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        amount = bound(amount, held + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function approvedOverdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool unlimited)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        amount = bound(amount, held + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;

        // The allowance is sufficient. A later balance failure must roll back its consumption.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        if (delegated) {
            uint256 approved = expectedAllowance[owner][spender];
            available = available < approved ? available : approved;
        }
        amount = bound(amount, 0, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function transferAllAndReturn(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        // At least one actor is funded by conservation. Select one without discarding the call.
        for (uint256 i; i < actors.length && expectedBalance[actors[fromIndex]] == 0; ++i) {
            fromIndex = (fromIndex + 1) % actors.length;
        }
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 held = expectedBalance[from];
        assertGt(held, 0, "round trip must move a positive balance");

        vm.prank(from);
        assertTrue(token.transfer(to, held));
        assertEq(token.balanceOf(from), 0, "full balance must be transferable");
        assertEq(token.balanceOf(to), expectedBalance[to] + held, "recipient must receive the full balance");
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(to);
        assertTrue(token.transfer(from, held));
        // A fee-free round trip must restore both balances and leave all allowances intact.
        assertEq(token.balanceOf(from), held);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SuperFrenPetInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SuperFrenPet private token;
    TokenHandler private handler;

    function setUp() public {
        token = new SuperFrenPet();
        handler = new TokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.overdraw.selector;
        selectors[4] = TokenHandler.revokeAndAttemptSpend.selector;
        selectors[5] = TokenHandler.approvedOverdraw.selector;
        selectors[6] = TokenHandler.transferToZero.selector;
        selectors[7] = TokenHandler.approveZeroSpender.selector;
        selectors[8] = TokenHandler.transferAllAndReturn.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner));
            sum += balance;
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Super Fren Pet");
        assertEq(token.symbol(), "SFP");
        assertEq(token.decimals(), 18);
    }
}
