// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TXTON Token
 * @notice Fixed-supply ERC20 with controlled minting, deposit-based burning, and airdrops.
 *
 * Key fixes & improvements:
 * - triggerBurnFromDeposits() burns only tokens recorded in BurnBalance (root cause fixed).
 * - burnDivisor is configurable by ADMIN_ROLE (with bounds).
 * - Added safety checks & events (AdminTransferred, ETHForwardFailed).
 * - Airdrop rejects zero-address recipients.
 */
contract TXTON is ERC20, ERC20Permit, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ────────────── Constants ──────────────
    uint256 public constant MAX_SUPPLY = 200_000_000 * 10 ** 6; // decimals = 6
    uint256 public constant MAX_AIRDROP_BATCH = 50;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    // ────────────── State Variables ──────────────
    uint64 public lastBurnTimestamp;
    uint64 public burnInterval = 365 days; // 1 year default
    address public admin;
    uint256 public initialSupply;
    uint256 public BurnBalance; // tokens deposited for burn

    // Configurable divisor: burnAmt = totalSupply() / burnDivisor
    uint256 public burnDivisor = 100_000_000; // default: ~0.001% per burn

    // ────────────── Events ──────────────
    event Burned(uint256 amount, uint256 timestamp);
    event Minted(address indexed to, uint256 amount);
    event BurnConfigUpdated(uint64 newInterval);
    event BurnDivisorUpdated(uint256 newDivisor);
    event ERC20Recovered(address indexed token, uint256 amount, address indexed to);
    event DepositForBurn(address indexed user, uint256 amount);
    event Airdropped(address indexed to, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event ETHForwardFailed(address indexed admin, uint256 amount);

    // ────────────── Constructor ──────────────
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        admin = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINT_ROLE, admin);

        // Initial mint: 20% to admin
        uint256 adminMint = (MAX_SUPPLY * 20) / 100;
        _mint(admin, adminMint);
        emit Minted(admin, adminMint);

        initialSupply = adminMint;
        lastBurnTimestamp = uint64(block.timestamp);
    }

    // ────────────── Views ──────────────
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function depositedBalance() external view returns (uint256) {
        return BurnBalance;
    }

    function contractBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    function nextBurnTime() external view returns (uint256) {
        return uint256(lastBurnTimestamp) + uint256(burnInterval);
    }

    function mintableSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    // ────────────── Admin Config ──────────────
    function updateBurnConfig(uint64 newInterval) external onlyRole(ADMIN_ROLE) {
        require(newInterval >= 1 days, "TXTON: too short");
        burnInterval = newInterval;
        emit BurnConfigUpdated(newInterval);
    }

    /**
     * @notice Update burn divisor (controls burn amount = totalSupply / burnDivisor)
     * @dev Only ADMIN_ROLE. Bounds enforced to prevent mistakes.
     */
    function updateBurnDivisor(uint256 newDivisor) external onlyRole(ADMIN_ROLE) {
        require(newDivisor > 0, "TXTON: invalid divisor");
        // safety bounds (adjust as you see fit)
        require(newDivisor >= 10_000 && newDivisor <= 1_000_000_000, "TXTON: out of range");
        burnDivisor = newDivisor;
        emit BurnDivisorUpdated(newDivisor);
    }

    // ────────────── Minting ──────────────
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) nonReentrant {
        require(to != address(0), "TXTON: zero address");
        require(amount > 0, "TXTON: zero amount");
        require(totalSupply() + amount <= MAX_SUPPLY, "TXTON: exceeds max supply");

        _mint(to, amount);
        emit Minted(to, amount);
    }

    // ────────────── Deposit & Burn ──────────────
    function depositForBurn(uint256 amount) external nonReentrant {
        require(amount > 0, "TXTON: zero amount");
        _transfer(msg.sender, address(this), amount);
        BurnBalance += amount;
        emit DepositForBurn(msg.sender, amount);
    }

    function adminBurn(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(amount > 0, "TXTON: zero amount");
        _burn(msg.sender, amount);
        emit Burned(amount, block.timestamp);
    }

    /**
     * @notice Trigger scheduled burn. Burns only from deposited tokens (BurnBalance).
     * @dev Uses burnDivisor to compute intended burn amount; actual burn is min(burnAmt, BurnBalance).
     */
    function triggerBurnFromDeposits() external onlyRole(BURN_ROLE) nonReentrant {
        require(block.timestamp >= lastBurnTimestamp + burnInterval, "TXTON: not due");

        uint256 burnAmt = totalSupply() / burnDivisor;
        require(burnAmt > 0, "TXTON: burn amount too small");

        uint256 burnFromDeposits = burnAmt <= BurnBalance ? burnAmt : BurnBalance;
        require(burnFromDeposits > 0, "TXTON: no deposited tokens to burn");

        BurnBalance -= burnFromDeposits;
        _burn(address(this), burnFromDeposits);

        lastBurnTimestamp = uint64(block.timestamp);
        emit Burned(burnFromDeposits, block.timestamp);
    }

    function burnAllDeposited() external onlyRole(BURN_ROLE) nonReentrant {
        uint256 bal = BurnBalance;
        require(bal > 0, "TXTON: no deposits");

        BurnBalance = 0;
        _burn(address(this), bal);
        emit Burned(bal, block.timestamp);
    }

    // ────────────── Airdrop ──────────────
    function airdrop(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(AIRDROP_ROLE)
        nonReentrant
    {
        uint256 len = recipients.length;
        require(len == amounts.length, "TXTON: array length mismatch");
        require(len <= MAX_AIRDROP_BATCH, "TXTON: batch too large");

        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "TXTON: zero recipient");
            uint256 amt = amounts[i];
            require(amt > 0, "TXTON: zero amount");
            require(totalSupply() + amt <= MAX_SUPPLY, "TXTON: exceeds max supply");
            _mint(recipients[i], amt);
            emit Airdropped(recipients[i], amt);
        }
    }

    // ────────────── ERC20 Recovery ──────────────
    function recoverERC20(address token, address to, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        require(token != address(this), "TXTON: cannot recover TXTON");
        require(to != address(0), "TXTON: zero address");
        require(amount > 0, "TXTON: zero amount");

        IERC20(token).safeTransfer(to, amount);
        emit ERC20Recovered(token, amount, to);
    }

    /// @notice Recovers TXTON tokens not part of deposits
    function recoverOwnToken(uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        require(to != address(0), "TXTON: zero address");
        require(amount > 0, "TXTON: zero amount");

        uint256 currentBalance = balanceOf(address(this));
        require(currentBalance > BurnBalance, "TXTON: nothing recoverable");

        uint256 available = currentBalance - BurnBalance;
        require(amount <= available, "TXTON: exceeds recoverable balance");

        _transfer(address(this), to, amount);
        emit ERC20Recovered(address(this), amount, to);
    }

    // ────────────── ETH Handling ──────────────
    receive() external payable nonReentrant {
        _sendETHToAdmin(msg.value);
    }

    fallback() external payable nonReentrant {
        _sendETHToAdmin(msg.value);
    }

    function _sendETHToAdmin(uint256 amount) internal {
        if (amount == 0) return;
        (bool success, ) = payable(admin).call{value: amount}("");
        if (!success) {
            emit ETHForwardFailed(admin, amount);
        }
    }

    function withdrawETH(address to, uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(to != address(0), "TXTON: zero address");
        require(address(this).balance >= amount, "TXTON: insufficient ETH");
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "TXTON: ETH withdraw failed");
        emit ETHWithdrawn(to, amount);
    }

    // ────────────── Allowance Helpers ──────────────
    // Note: not marked override to support multiple OZ versions
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "TXTON: decreased below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    // ────────────── Admin Transfer ──────────────
    function transferAdmin(address newAdmin) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(newAdmin != address(0), "TXTON: zero address");

        address prevAdmin = admin;

        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _grantRole(ADMIN_ROLE, newAdmin);
        _grantRole(MINT_ROLE, newAdmin);

        _revokeRole(ADMIN_ROLE, admin);
        _revokeRole(DEFAULT_ADMIN_ROLE, admin);
        _revokeRole(MINT_ROLE, admin);

        admin = newAdmin;
        emit AdminTransferred(prevAdmin, newAdmin);
    }

    function renounceAdminRole() external onlyRole(ADMIN_ROLE) nonReentrant {
        renounceRole(ADMIN_ROLE, msg.sender);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        renounceRole(MINT_ROLE, msg.sender);
    }
}
