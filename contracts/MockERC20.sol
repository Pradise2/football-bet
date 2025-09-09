// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ===============================================
// CONTRACT: MockERC20 (Configurable Test Token)
// ===============================================

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    // ===================================================
    // CONSTRUCTOR
    // ===================================================
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        _decimals = decimals_;
        if (initialSupply > 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    // ===================================================
    // METADATA OVERRIDE
    // ===================================================
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // ===================================================
    // MINT FUNCTIONS
    // ===================================================

    /// @notice Mint new tokens (owner only)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Public faucet for testing (anyone can mint to themselves)
    /// @dev Use only in local/test deployments — remove for production
    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    // ===================================================
    // BURN FUNCTIONS
    // ===================================================

    /// @notice Burn tokens from caller’s balance
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn tokens from another account (requires allowance)
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
