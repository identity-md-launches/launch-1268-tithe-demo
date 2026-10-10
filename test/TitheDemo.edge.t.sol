// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TitheDemo} from "src/TitheDemo.sol";

/// @dev Complements the deployment and ERC-20 tests with repeated calls, aliasing,
/// allowance boundaries, and properties over more than one operation.
/// forge-config: default.fuzz.runs = 1000
contract TitheDemoEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant MAX = type(uint256).max;

    TitheDemo internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal otherSpender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new TitheDemo();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function test_OneBaseUnitRoundTripDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAndSelfTransferRevert() public {
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, MAX);
        vm.expectRevert(error);
        token.transfer(bob, MAX);
        vm.expectRevert(error);
        token.transfer(address(this), MAX);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceCannotSpendMaximumAmountWithoutBalance() public {
        assertTrue(token.approve(spender, MAX));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, MAX)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, MAX);
        assertEq(token.allowance(address(this), spender), MAX);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceDecreasesOnEverySpend() public {
        assertTrue(token.approve(spender, MAX - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), MAX - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), MAX - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullSupplyDelegatedTransferCannotReuseExhaustedApproval() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_CompetingSpendersCannotOverdrawAndFailedSpendKeepsApproval() public {
        assertTrue(token.transfer(alice, 10));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 10));
        assertTrue(token.approve(otherSpender, 10));
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(alice, otherSpender, 1);
        assertEq(token.allowance(alice, otherSpender), 10);
        assertEq(token.balanceOf(otherSpender), 0);

        assertTrue(token.transfer(alice, 1));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, otherSpender, 1));
        assertEq(token.allowance(alice, otherSpender), 9);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 10);
        assertEq(token.balanceOf(otherSpender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 11);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ReducedAllowanceImmediatelyLimitsTheSpender() public {
        assertTrue(token.approve(spender, 10));
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBecomeFiniteAfterUse() public {
        assertTrue(token.approve(spender, MAX));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        assertEq(token.allowance(address(this), spender), MAX);
        assertTrue(token.approve(spender, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 8);
        assertEq(token.balanceOf(address(this)), SUPPLY - 8);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerAlsoNeedsApprovalToUseTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesApproval() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferStillRejectsZeroRecipient() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), MAX];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroAndMaximumApprovalsStillRejectZeroSpender() public {
        assertTrue(token.approve(spender, 9));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), MAX);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 9);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresFundedHolders(uint256 aliceSeed, uint256 bobSeed, uint256 amountSeed)
        public
    {
        uint256 aliceBalance = bound(aliceSeed, 1, SUPPLY);
        uint256 bobBalance = bound(bobSeed, 0, SUPPLY - aliceBalance);
        uint256 amount = bound(amountSeed, 1, aliceBalance);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, bobBalance));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.balanceOf(bob), bobBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedSpendMatchesSingleSpend(
        uint256 allowanceSeed,
        uint256 amountSeed,
        uint256 firstSeed
    ) public {
        uint256 allowed = bound(allowanceSeed, 1, MAX - 1);
        uint256 limit = allowed < SUPPLY / 2 ? allowed : SUPPLY / 2;
        uint256 amount = bound(amountSeed, 1, limit);
        uint256 first = bound(firstSeed, 0, amount);
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.transfer(bob, SUPPLY / 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        vm.prank(bob);
        assertTrue(token.approve(spender, allowed));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(alice, address(this), first));
        assertTrue(token.transferFrom(alice, address(this), amount - first));
        assertTrue(token.transferFrom(bob, address(this), amount));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), token.balanceOf(bob));
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(address(this)), 2 * amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), allowed - amount);
        assertEq(token.allowance(bob, spender), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsReplaceRatherThanAccumulateAndAreIsolated(uint256 first, uint256 replacement) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(otherSpender, first));
        vm.prank(alice);
        assertTrue(token.approve(spender, first));

        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), first);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFundingWithoutReapproval(
        uint256 balanceSeed,
        uint256 deficitSeed,
        uint256 allowanceSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 deficit = bound(deficitSeed, 1, SUPPLY - balance);
        uint256 amount = balance + deficit;
        uint256 allowed = bound(allowanceSeed, amount, MAX - 1);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, deficit));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), allowed - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransfersCannotHideInsufficientBalance(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, MAX);
        assertTrue(token.transfer(alice, balance));
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount);
        vm.expectRevert(error);
        vm.prank(alice);
        token.transfer(alice, amount);

        vm.prank(alice);
        assertTrue(token.approve(spender, MAX));
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(alice, alice, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), MAX);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferToTokenItselfDoesNotBurn(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        assertTrue(token.transfer(address(token), amount));
        assertEq(token.balanceOf(address(token)), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
