// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Sells up to 10 NFTs for 10 PaymentToken each. The owner withdraws the proceeds.
contract PurchasableNFT is ERC721, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE = 10 * 10 ** 18;
    uint256 public constant MAX_SUPPLY = 10;

    IERC20 public immutable paymentToken;

    /// ID of the next NFT. Also the number of NFTs minted so far.
    uint256 public nextTokenId;

    error ZeroAddress();
    error SoldOut();

    constructor(address token) ERC721("PurchasableNFT", "PNFT") Ownable(msg.sender) {
        if (token == address(0)) revert ZeroAddress();
        paymentToken = IERC20(token);
    }

    /// Buys the next NFT for `PRICE` tokens. The caller must approve `PRICE` first.
    function mint() external {
        uint256 tokenId = nextTokenId;
        if (tokenId >= MAX_SUPPLY) revert SoldOut();

        // Update the counter before any external call: _safeMint calls back into the receiver.
        nextTokenId = tokenId + 1;

        paymentToken.safeTransferFrom(msg.sender, address(this), PRICE);
        _safeMint(msg.sender, tokenId);
    }
}
