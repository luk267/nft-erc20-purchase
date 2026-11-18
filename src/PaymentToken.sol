// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Payment token for PurchasableNFT. For testing only: anyone can mint.
contract PaymentToken is ERC20 {
    constructor() ERC20("PaymentToken", "PAY") {}

    /// Mints `amount` tokens to `to`. Callable by anyone.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
