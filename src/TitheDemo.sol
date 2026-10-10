// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Tithe Demo
/// @notice A fixed supply of one billion TDEMO, with 18 decimals and exact ERC-20 transfers.
/// @dev The immediate deployer receives the entire supply. No minting, burning, or admin entry points exist.
contract TitheDemo is ERC20 {
    /// @notice Total issuance in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Tithe Demo", "TDEMO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
