// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "../src/SuperFrenPet.sol";

/// @dev Test-only deployment fixture; never part of the production deployment.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (SuperFrenPet) {
        return new SuperFrenPet{salt: salt}();
    }

    function send(SuperFrenPet token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract SuperFrenPetTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    SuperFrenPet private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new SuperFrenPet();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Super Fren Pet");
        assertEq(token.symbol(), "SFP");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new SuperFrenPet();
    }

    function test_AccountDeploymentMintsToDeployer() public {
        vm.prank(alice);
        SuperFrenPet deployed = new SuperFrenPet();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_Create2DeploymentMintsToFactory() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("SFP test deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(SuperFrenPet).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(alice, alice);
        SuperFrenPet deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndMoveBack() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRevertsForInsufficientBalance() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        token.transfer(bob, 11 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferCannotExceedBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndDoesNotMoveFunds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalCanBeReplacedAndRevoked() public {
        token.approve(spender, 50 ether);
        token.approve(spender, 20 ether);
        assertEq(token.allowance(address(this), spender), 20 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalIsScopedToOwnerAndSpender() public {
        token.approve(spender, 50 ether);
        vm.prank(alice);
        token.approve(spender, 7 ether);
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.allowance(alice, spender), 7 ether);
        assertEq(token.allowance(address(this), bob), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromSpendsFiniteAllowance() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertEq(token.allowance(address(this), spender), 30 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(alice), 20 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 30 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 50 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromPreservesInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromRevertsForInsufficientAllowance() public {
        token.approve(spender, 9 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 9 ether, 10 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10 ether);
        assertEq(token.allowance(address(this), spender), 9 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroRecipientRollsBackAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_NoMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(alice, 10 ether);
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("setMinter(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertFalse(fromDeployer, "unexpected deployer capability");
            vm.prank(bob);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertFalse(fromStranger, "unexpected public capability");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
    }

    /// @dev Exercises token accounting only; the network's protected suite tests actual pool swaps.
    function test_LaunchDistributionClaimsAndPoolTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        SuperFrenPet deployed = factory.deploy(keccak256("launch accounting"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainder = makeAddr("remainder");
        assertTrue(factory.send(deployed, distributor, SUPPLY / 10));
        assertTrue(factory.send(deployed, poolManager, SUPPLY * 8 / 10));
        assertTrue(factory.send(deployed, remainder, SUPPLY / 10));
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), SUPPLY / 10);
        assertEq(deployed.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(deployed.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, SUPPLY / 10));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), SUPPLY / 10);
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, 123 ether));
        assertEq(deployed.balanceOf(bob), 123 ether);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, 123 ether));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromConservesSupplyAndAccountsForAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutChangingSupply(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
