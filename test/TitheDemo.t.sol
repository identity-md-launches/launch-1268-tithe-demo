// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TitheDemo} from "../src/TitheDemo.sol";

/// @dev Test-only factory: exercises the same immediate-caller ownership as a CREATE2 launch.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (TitheDemo) {
        return new TitheDemo{salt: salt}();
    }
}

/// @dev A recipient that rejects calls, proving ERC-20 transfers do not invoke recipient code.
contract RejectingRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

contract TitheDemoTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    TitheDemo internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new TitheDemo();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Tithe Demo");
        assertEq(token.symbol(), "TDEMO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        TitheDemo deployed = new TitheDemo();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2MintsEverythingToFactory() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("TDEMO deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(TitheDemo).creationCode))
                    )
                )
            )
        );
        vm.prank(alice);
        TitheDemo deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 17 ether);
        assertTrue(token.transfer(alice, 17 ether));
        assertEq(token.balanceOf(alice), 17 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 17 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractNeedsNoCallback() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenZeroTransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_ApproveReplacesAndRevokesAllowanceWithEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 10 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);

        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalDoesNotRequireCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 6 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 6 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowancePersistsAndCanBeRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 9 ether));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 9 ether);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfStillConsumesAllowance() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 1 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenAllowanceIsInsufficient() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1 ether, 2 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2 ether);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenDifferentSpenderUsesApproval() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1 ether);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenDeployerSpendsHolderFundsWithoutApproval() public {
        assertTrue(token.transfer(alice, 5 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_RevertWhenBalanceIsInsufficientRestoresAllowance() public {
        assertTrue(token.transfer(alice, 1 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 2 ether);
        assertEq(token.allowance(alice, spender), 2 ether);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(spender, 2 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), spender), 2 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferFromZero() public {
        // Zero value gets past the allowance comparison but cannot make a zero sender valid.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LaunchDistributionAndSubsequentTransfersAreExact() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        TitheDemo launched = factory.deploy(keccak256("launch flow"));
        address distributor = makeAddr("distributor probe");
        address pool = makeAddr("pool custody probe");
        address remainder = makeAddr("remainder probe");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 88 / 100;
        uint256 remainderShare = SUPPLY * 2 / 100;

        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarmShare));
        assertTrue(launched.transfer(pool, poolShare));
        assertTrue(launched.transfer(remainder, remainderShare));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 10 ether));
        assertEq(launched.balanceOf(bob), 10 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 10 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnOrAdministrativeEntrypoints() public {
        assertTrue(token.transfer(alice, 5 ether));
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("initialize(address)", bob);
        calls[3] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[4] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[5] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[8] = abi.encodeWithSignature("freezeAccount(address)", alice);
        calls[9] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[10] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[11] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[12] = abi.encodeWithSignature("seize(address)", alice);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 5 ether);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 5 ether));
        assertEq(token.balanceOf(bob), 5 ether);
    }

    function test_RuntimeIsDeployableAndContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromAccounting(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowed = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, allowed);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), allowed - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExcessiveTransferRevertsWithoutMutation(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExcessiveSpendRevertsWithoutMutation(uint256 rawAllowance, uint256 rawExcess) public {
        uint256 allowed = bound(rawAllowance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - allowed);
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + excess)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, allowed + excess);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
