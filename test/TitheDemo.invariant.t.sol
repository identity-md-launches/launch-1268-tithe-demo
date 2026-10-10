// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TitheDemo} from "../src/TitheDemo.sol";

/// @dev Test-only handler. All tokens stay among these actors, allowing a complete balance sum.
contract TitheDemoHandler is Test {
    TitheDemo public immutable token;
    address[4] public actors;

    constructor() {
        token = new TitheDemo();
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        uint256 share = token.totalSupply() / actors.length;
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], share), "initial transfer failed");
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 limit = allowance < balance ? allowance : balance;
        uint256 amount = bound(amountSeed, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

contract TitheDemoInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TitheDemoHandler internal handler;
    TitheDemo internal token;

    function setUp() public {
        handler = new TitheDemoHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TitheDemoHandler.transfer.selector;
        selectors[1] = TitheDemoHandler.approve.selector;
        selectors[2] = TitheDemoHandler.transferFrom.selector;
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
}
