# Super Fren Pet (SFP)

An immutable ERC-20 token. The constructor mints **1,000,000,000 SFP**, with
**18 decimals**, entirely to `msg.sender`, the immediate deployer. The supply in
base units is **1000000000000000000000000000** (`10^27`).

The production contract is [`src/SuperFrenPet.sol`](src/SuperFrenPet.sol), Solidity
identifier **`SuperFrenPet`**. It uses the vendored OpenZeppelin Contracts v5.1.0
ERC-20 implementation. The only added behavior is the constructor's one-time mint.

## Behavior and assumptions

- Name: `Super Fren Pet`; symbol: `SFP`; decimals: `18`.
- Transfers deliver the exact requested amount, including transfers to and from
  factories, distributors, pools, and ordinary holders. There are no taxes,
  transfer limits, rebases, or address exemptions.
- There are no externally callable mint or burn functions. Total supply remains
  fixed after construction.
- There is no owner, minter, pauser, blacklist, seizure mechanism, proxy, upgrade
  function, or post-deployment initialization.
- Standard ERC-20 transfers and approvals return `true` on success and revert on
  failure with OpenZeppelin's ERC-6093 custom errors. Zero-value transfers between
  valid addresses succeed and emit `Transfer`. Transfers to the zero address and
  approvals to a zero spender revert.
- `approve` replaces the allowance. Finite allowances decrease on `transferFrom`;
  `type(uint256).max` is an unlimited allowance and does not decrease. Successful
  approvals emit `Approval`; spending an allowance emits `Transfer` without an
  additional `Approval` event. Integrations should query `allowance` for its
  current value.
- The token does not call external contracts or invoke recipient callbacks.
  It does not accept ordinary ETH transfers and has no asset recovery mechanism.
  Tokens sent to this token contract itself, or another contract without a
  withdrawal mechanism, can become inaccessible.

These semantics follow [ERC-20](https://eips.ethereum.org/EIPS/eip-20) and the
vendored [OpenZeppelin implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/69c8def5f222ff96f2b5beff05dfba996368aa79/contracts/token/ERC20/ERC20.sol).

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization at 200 runs,
and `bytecode_hash = "none"`. Dependencies are ordinary source files under `lib/`;
there are no submodules or installation steps. Builds and tests need no network
once Foundry and the pinned compiler are installed. FFI and filesystem permissions
are not enabled. Tests use no RPC, wallet keys, environment variables, or external
services.

`test/SuperFrenPet.t.sol` covers metadata, mint events, account and CREATE2 factory
deployment, exact transfers, self/zero transfers, approval replacement/revocation,
finite/infinite allowances, invalid addresses, insufficient balances/allowances,
failure rollback, absence of administrative capabilities, and launch transfer
accounting. Fuzz tests exercise arbitrary recipients, amounts, and allowances.
`test/SuperFrenPet.invariant.t.sol` checks supply conservation and independently
modeled balances and allowances after randomized sequences of transfers,
approvals, and delegated transfers. Default settings are 1,024 runs per fuzz test
and 128 invariant runs of up to 64 calls each.

The launch accounting test models token transfers only. Actual Uniswap pool
initialization, liquidity settlement, and swaps belong to the separately supplied
network launch harness and are not simulated as proof of a live pool here.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Artifact | `src/SuperFrenPet.sol:SuperFrenPet` |
| Intended launch chain | Ethereum, chain ID 1 |
| Constructor arguments | None; empty argument list |
| Deployment ETH value | 0 |
| Initial supply recipient | Immediate constructor caller (`msg.sender`) |
| Supply in base units | `1000000000000000000000000000` |
| External contracts / linked libraries | None |
| Initialization / configuration calls | None |

The launch system deploys this creation bytecode directly. When its factory calls
CREATE or CREATE2, **the factory receives the entire supply**, even if a different
wallet originated the transaction. The constructor neither contacts external
contracts nor distributes supply onward. A direct account deployment instead
mints to that account. A deployment helper must be able to forward its balance;
there is no later admin recovery action.

To inspect deployment artifacts without sending a transaction:

```sh
forge inspect src/SuperFrenPet.sol:SuperFrenPet abi
forge inspect src/SuperFrenPet.sol:SuperFrenPet bytecode
forge inspect src/SuperFrenPet.sol:SuperFrenPet deployedBytecode
```

The separate network manifest step owns `launch.json`, constructor argument
encoding, factory selection, pool settings, and distribution. Per this assignment,
the factory distributes 10% to its contributor distributor, uses 80% for the pool,
and forwards the remaining 10% under the supplied launch economics. Those actions
are external to this token and create no minting or control privileges. There are
no application contracts in this deliverable.

## After launch and operational responsibilities

There are no owner settings, services, scheduled tasks, or maintenance calls.
The launch operator is responsible for deploying the reviewed artifact with the
pinned build settings, forwarding the initial supply through the agreed launch
flows, verifying deployed source, and confirming metadata, total supply, and
distribution from receipts and balances. No deployment or broadcast is performed
by this project.

Holders control their own balances and allowances. Wallet integrations should use
limited approvals where possible and offer revocation. When changing an existing
nonzero allowance, revoke it and confirm that transaction before granting the new
amount; an already authorized spender can spend while transactions are pending.
The deployer has no authority to restore lost tokens, reverse a transfer, or freeze
an account.

Foundry tests and a local source review are validation, not an independent security
audit. The launch operator remains responsible for the network's independent
adversarial review before release. Slither, Mythril, live-chain integration,
deployment, and explorer verification are not part of the local validation.

## Vendored dependencies

[`DEPENDENCIES.json`](DEPENDENCIES.json) records versions, immutable upstream commit
IDs, archive hashes, and SHA-256 hashes for each vendored file:

- OpenZeppelin Contracts v5.1.0: the ERC-20 dependency closure and MIT license.
- forge-std v1.9.7: test sources and MIT / Apache-2.0 licenses.

Vendored sources are unmodified. Project source and tests are MIT licensed; see
[`LICENSE`](LICENSE).
