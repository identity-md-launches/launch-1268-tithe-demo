// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TitheDemo} from "../src/TitheDemo.sol";

/// @dev Test-only handler. All tokens stay among these actors, allowing a complete balance sum.
contract TitheDemoHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    TitheDemo public immutable token;
    address[4] public actors;
    // This ledger is driven by requested operations, never copied from token getters.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new TitheDemo();
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        expectedBalance[address(this)] = SUPPLY;
        uint256 share = SUPPLY / actors.length;
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], share), "initial transfer failed");
            expectedBalance[address(this)] -= share;
            expectedBalance[actors[i]] = share;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = _boundaryAmount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Exercise revocation and the finite/infinite boundary frequently, while retaining
        // unrestricted uint256 approvals (an allowance need not fit the owner's balance).
        uint256 mode = amountSeed % 5;
        uint256 amount = mode == 0
            ? 0
            : mode == 1 ? 1 : mode == 2 ? type(uint256).max : mode == 3 ? type(uint256).max - 1 : amountSeed;
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 limit = allowance < balance ? allowance : balance;
        uint256 amount = _boundaryAmount(amountSeed, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordTransfer(owner, to, amount);
        assertEq(token.allowance(owner, spender), expectedAllowance[owner][spender]);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ledger update: the invariants require all balances AND allowances to survive failure.
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowanceSeed)
        public
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = _boundaryAmount(allowanceSeed, expectedBalance[owner]);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
    }

    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = _boundaryAmount(amountSeed, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function _boundaryAmount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        uint256 mode = seed % 4;
        if (mode == 0) return 0;
        if (mode == 1) return limit == 0 ? 0 : 1;
        if (mode == 2) return limit;
        return bound(seed, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract TitheDemoInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TitheDemoHandler internal handler;
    TitheDemo internal token;

    function setUp() public {
        handler = new TitheDemoHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = TitheDemoHandler.transfer.selector;
        selectors[1] = TitheDemoHandler.approve.selector;
        selectors[2] = TitheDemoHandler.transferFrom.selector;
        selectors[3] = TitheDemoHandler.transferOverBalance.selector;
        selectors[4] = TitheDemoHandler.transferFromOverAllowance.selector;
        selectors[5] = TitheDemoHandler.transferFromOverBalance.selector;
        selectors[6] = TitheDemoHandler.rejectZeroReceiver.selector;
        selectors[7] = TitheDemoHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_AllBalancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertLe(balance, SUPPLY);
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_EachHolderHasExactlyTheirTokens() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder ledger mismatch");
        }
    }

    function invariant_AllAllowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance mismatch"
                );
            }
        }
    }
}
