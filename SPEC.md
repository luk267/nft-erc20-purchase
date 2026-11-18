# SPEC: Buy an NFT with an ERC20 token

## Purpose
A buyer pays with an ERC20 token and receives an NFT in return.
There are at most 10 NFTs. Each costs 10 tokens.
The tokens accumulate in the NFT contract. Only the owner can withdraw them.

## Contracts
| Contract | Base | Name / Symbol | Role |
|---|---|---|---|
| `PaymentToken` | OpenZeppelin `ERC20` | `PaymentToken` / `PAY` | Payment token for testing. Anyone can mint. |
| `PurchasableNFT` | OpenZeppelin `ERC721` + `Ownable` | `PurchasableNFT` / `PNFT` | Sells NFTs for `PaymentToken`. |

## Roles
- **Owner:** The address that deploys `PurchasableNFT`. May withdraw the token balance.
- **Buyer:** Any address. May buy NFTs while some are left.
- **Anyone:** May mint `PaymentToken`.

## Constants and state
- `PRICE`: 10 tokens, i.e. `10 * 10**18` (the token has 18 decimals). `constant`.
- `MAX_SUPPLY`: 10. `constant`.
- `paymentToken`: address of `PaymentToken`. `immutable`, set in the constructor.
- `nextTokenId`: ID of the next NFT. Starts at 0. Also equals the number of NFTs minted so far. IDs are 0 to 9.

## Errors
| Error | When |
|---|---|
| `ZeroAddress()` | The constructor receives `address(0)` as token. |
| `SoldOut()` | `mint()` when `MAX_SUPPLY` NFTs already exist. |
| `NothingToWithdraw()` | `withdraw()` when the token balance is 0. |
| `RenounceOwnershipDisabled()` | Every call to `renounceOwnership()`. |

OpenZeppelin errors apply in addition, for example `ERC20InsufficientAllowance` and `OwnableUnauthorizedAccount`.
If the token itself reverts, `SafeERC20` bubbles up its error unchanged. `SafeERC20FailedOperation` only occurs if a token returns `false`.

## Functions

### PaymentToken
- `mint(address to, uint256 amount)`: mints `amount` tokens to `to`. Callable by anyone.
  Reverts if `to == address(0)` (from OpenZeppelin).

### PurchasableNFT
- `constructor(address token)`: sets `paymentToken` and makes `msg.sender` the owner.
  Reverts with `ZeroAddress()` if `token == address(0)`.
- `mint()`: pulls `PRICE` tokens from the caller to the NFT contract and mints the next NFT to the caller with `_safeMint`.
  - The buyer must first call `approve(nft, PRICE)` on the token.
  - Order (checks-effects-interactions):
    1. Check: `nextTokenId < MAX_SUPPLY`, otherwise `SoldOut()`.
    2. Effect: increment `nextTokenId`.
    3. Interaction: `safeTransferFrom` (OpenZeppelin `SafeERC20`) pulls `PRICE` tokens.
    4. Interaction: `_safeMint` mints the NFT and calls back into a receiver contract.
  - Reverts if the allowance is below `PRICE` (OpenZeppelin).
  - Reverts if the token balance is below `PRICE` (OpenZeppelin).
  - Reverts if the caller is a contract that does not implement `onERC721Received` correctly (OpenZeppelin).
- `withdraw()`: transfers the entire token balance of the NFT contract to the owner with `safeTransfer`.
  - Reverts if the caller is not the owner (`onlyOwner`).
  - Reverts with `NothingToWithdraw()` if the balance is 0.
- `renounceOwnership()`: overrides the `Ownable` function and always reverts with `RenounceOwnershipDisabled()`.

Out of scope: per-address limit, price changes, refunds, metadata (`tokenURI`), `Ownable2Step`.

## Invariants
Each line becomes a test. In brackets: unit (U) or fuzz (F).

1. There are never more than `MAX_SUPPLY` NFTs. (U: the eleventh purchase reverts with `SoldOut()`. F: any number of purchases.)
2. Every successful `mint()` lowers the buyer's token balance by exactly `PRICE` and raises the NFT contract's balance by exactly `PRICE`. (U, F)
3. Every successful `mint()` raises the buyer's NFT count by exactly 1. (U)
4. Every token ID is assigned at most once. IDs ascend from 0 without gaps. `nextTokenId` equals the number of minted NFTs. (U)
5. No payment, no NFT: if the payment reverts, no state changes. (U)
6. After `withdraw()`, the NFT contract's token balance is 0. The owner's balance has risen by exactly the previous amount. (U, F)
7. Only the owner can successfully call `withdraw()`. (U, F: any caller)
8. The owner is never `address(0)`. (U: `renounceOwnership()` and `transferOwnership(address(0))` revert.)
9. `paymentToken`, `PRICE` and `MAX_SUPPLY` never change after deployment. (Enforced by the compiler through `immutable` and `constant`; no separate test needed.)

## Threats
| Attacker | Attempt | Defense |
|---|---|---|
| Buyer | Get an NFT without paying | `transferFrom` reverts without allowance or balance. Payment happens before minting. |
| Buyer | Mint more than 10 NFTs | `nextTokenId` is checked against `MAX_SUPPLY` |
| Receiver contract | Reentrancy through the `_safeMint` callback | Checks-effects-interactions: counter and payment are done before the callback runs. |
| Stranger | Call `withdraw()` | `onlyOwner` |
| Owner | `renounceOwnership()`, locking the tokens | Function overridden, always reverts |
| Owner | `transferOwnership()` to a wrong address | Not defended. See trust assumptions. |
| Deployer | Zero address as token, making the contract useless | `ZeroAddress()` in the constructor |

## Trust assumptions
- The payment token is the project's own `PaymentToken`. It is a standard ERC20 without transfer fees. A fee-on-transfer token would break invariant 2.
- Anyone can mint `PaymentToken`, so the NFT is effectively free. This is intended, because the token exists for testing only.
- The owner is trusted to withdraw. The owner cannot take NFTs away or change price or supply cap.
- If the owner hands the role to a wrong address with `transferOwnership()`, the tokens are locked. `Ownable2Step` would prevent this (out of scope for this spec).
- Tokens sent directly to the NFT contract without a purchase go to the owner on `withdraw()`.
