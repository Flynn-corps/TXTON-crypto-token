🪙 TXTON Token

TXTON is a fixed-supply ERC20 token built with Solidity and OpenZeppelin, designed for secure, transparent, and controlled token management. It introduces advanced administrative controls, deposit-based burning, and automated airdrops — all backed by robust role-based access and safety mechanisms.

🔑 Core Features

Fixed Supply: Capped at 200,000,000 TXTON (6 decimals).

Controlled Minting: Only authorized addresses can mint tokens, ensuring total supply integrity.

Deposit-Based Burning: Users can deposit tokens to be burned later through a scheduled mechanism.

Configurable Burn Logic: Adjustable burn interval and divisor let admins fine-tune the deflation schedule.

Batch Airdrops: Distribute tokens to up to 50 recipients per transaction efficiently.

Safe Recovery: Recover mistakenly sent ERC20s or excess TXTON without affecting user deposits.

ETH Handling: Automatically forwards incoming ETH to the admin with fail-safes.

🧠 Security

Built on OpenZeppelin contracts for proven reliability.

Uses AccessControl for strict role-based permissions (ADMIN_ROLE, MINT_ROLE, BURN_ROLE, AIRDROP_ROLE).

ReentrancyGuard and SafeERC20 protect all external operations.

Full event logging for transparency and auditability.

⚙️ Tokenomics

Max Supply: 200,000,000 TXTON

Initial Mint: 20% (40,000,000 TXTON) to admin on deployment

Burn Divisor (default): 100,000,000 (~0.001% per burn)

Burn Interval (default): 365 days

🧩 Use Cases

Long-term ecosystems needing controlled token issuance.

Projects implementing periodic or user-triggered burns.

Communities requiring transparent and auditable token distribution via airdrops.

🧾 License

MIT License — open for community use, modification, and auditing.

TXTON combines transparency, safety, and flexibility in one ERC20 contract — built for modern, secure, and deflationary token economies.
