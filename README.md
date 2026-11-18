# nft-erc20-purchase

An NFT collection that can only be bought with one specific ERC20 token.
Each NFT costs 10 tokens. At most 10 NFTs exist. The owner withdraws the proceeds.

The full specification, with invariants, threats and trust assumptions, is in [SPEC.md](SPEC.md).

Built on [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) 5.7.0 and tested with [Foundry](https://getfoundry.sh/).

## Contracts

| Contract | Description |
|---|---|
| [`PaymentToken`](src/PaymentToken.sol) | ERC20 `PAY`. Anyone can mint it, because it exists for testing only. |
| [`PurchasableNFT`](src/PurchasableNFT.sol) | ERC721 `PNFT`. `mint()` takes 10 `PAY` from the buyer and mints the next NFT. `withdraw()` sends all `PAY` to the owner. |

A buyer first calls `approve(nft, 10e18)` on `PaymentToken`, then `mint()` on `PurchasableNFT`.

## Build and test

```shell
git clone --recursive https://github.com/luk267/nft-erc20-purchase.git
cd nft-erc20-purchase
forge build
forge test
```

If you cloned without `--recursive`, run `git submodule update --init --recursive` first.

## Design decisions

- **Checks-effects-interactions in `mint()`.** The counter goes up before the token transfer and before `_safeMint`. `_safeMint` calls back into contract buyers, so a buyer that re-enters `mint()` already sees the new counter.
- **`SafeERC20` for every token transfer.** A token that returns `false` instead of reverting cannot count as a payment.
- **`renounceOwnership()` always reverts.** Without an owner, the proceeds would be locked forever.
- **`withdraw()` pays `owner()`, not `msg.sender`.** Under `onlyOwner` both are the same. If the modifier were ever removed, the payout would still go to the owner.
- **`immutable` token address, `constant` price and cap.** None of them can change after deployment.

## Tests

27 tests: unit tests for normal use and failure cases, one reentrancy attack and 6 fuzz tests (256 runs each by default).

| Invariant from SPEC.md | Tests |
|---|---|
| 1. At most 10 NFTs | `test_Mint_AllTenNftsCanBeSold`, `test_RevertWhen_MintAfterSoldOut`, `testFuzz_SupplyNeverExceedsMax` |
| 2. Each purchase moves exactly the price | `test_Mint_MovesPriceFromBuyerToContract`, `testFuzz_Mint_MovesExactlyPrice` |
| 3. Each purchase gives exactly one NFT | `test_Mint_GivesOneNftToBuyer` |
| 4. IDs ascend from 0 without gaps | `test_Mint_AssignsAscendingIdsFromZero` |
| 5. No payment, no NFT | `test_RevertWhen_MintWithoutApproval`, `test_RevertWhen_MintWithoutBalance`, `test_RevertWhen_ContractCannotReceiveNft`, `testFuzz_RevertWhen_AllowanceBelowPrice` |
| 6. `withdraw()` sends the whole balance to the owner | `test_Withdraw_SendsWholeBalanceToOwner`, `testFuzz_Withdraw_SendsExactBalance` |
| 7. Only the owner can withdraw | `test_RevertWhen_StrangerWithdraws`, `testFuzz_RevertWhen_NonOwnerWithdraws` |
| 8. The owner is never `address(0)` | `test_RevertWhen_OwnerRenouncesOwnership`, `test_RevertWhen_TransferOwnershipToZeroAddress`, `testFuzz_RevertWhen_AnyoneRenouncesOwnership` |
| 9. Token, price and cap never change | Enforced by the compiler through `immutable` and `constant` |

`test_Reentrancy_EachReentryPaysAndCapHolds` uses a buyer contract that calls `mint()` again from `onERC721Received`.
It ends with all 10 NFTs and has paid for each of them.
The remaining tests cover the constructor, the custom errors, contract buyers and direct token transfers.

## Security

This is a learning project. It has not been audited. Do not use it with real funds.

Static analysis:
- Slither 0.11.6 reports no findings. Its `incorrect-equality` warning on `balance == 0` in `withdraw()` is a false positive and is suppressed in the code: other addresses can only raise the balance, never set it to 0.
- `forge lint` reports no findings.

Known limitations, accepted for this scope:
- Ownership moves in one step. A transfer to a wrong address locks the proceeds. `Ownable2Step` would prevent this.
- Anyone can mint `PaymentToken`, so the NFTs are effectively free.
- Tokens or NFTs other than `PAY` that are sent to the contract by mistake are stuck.
- The contract assumes a standard ERC20 without transfer fees. A fee-on-transfer token would break invariant 2.

## License

[MIT](LICENSE)
