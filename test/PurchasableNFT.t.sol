// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {PurchasableNFT} from "../src/PurchasableNFT.sol";

/// Contract buyer that accepts NFTs, to cover the `_safeMint` callback path.
contract ReceiverBuyer is IERC721Receiver {
    function buy(PaymentToken token, PurchasableNFT nft, uint256 price) external {
        token.approve(address(nft), price);
        nft.mint();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract PurchasableNFTTest is Test {
    PaymentToken internal token;
    PurchasableNFT internal nft;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Written down independently of the contract, so a wrong constant there makes the tests fail.
    uint256 internal constant PRICE = 10 * 10 ** 18;
    uint256 internal constant START_BALANCE = 100 * 10 ** 18;

    function setUp() public {
        token = new PaymentToken();

        vm.prank(owner);
        nft = new PurchasableNFT(address(token));

        token.mint(alice, START_BALANCE);
        token.mint(bob, START_BALANCE);
    }

    function _buy(address buyer) internal {
        vm.startPrank(buyer);
        token.approve(address(nft), PRICE);
        nft.mint();
        vm.stopPrank();
    }

    // --- constructor ---

    function test_Constructor_SetsInitialState() public view {
        assertEq(address(nft.paymentToken()), address(token));
        assertEq(nft.owner(), owner);
        assertEq(nft.nextTokenId(), 0);
        assertEq(nft.PRICE(), PRICE);
        assertEq(nft.MAX_SUPPLY(), 10);
        assertEq(nft.name(), "PurchasableNFT");
        assertEq(nft.symbol(), "PNFT");
    }

    // --- mint ---

    // Invariant 2
    function test_Mint_MovesPriceFromBuyerToContract() public {
        _buy(alice);

        assertEq(token.balanceOf(alice), START_BALANCE - PRICE);
        assertEq(token.balanceOf(address(nft)), PRICE);
    }

    // Invariant 3
    function test_Mint_GivesOneNftToBuyer() public {
        _buy(alice);

        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.ownerOf(0), alice);
    }

    // Invariant 4
    function test_Mint_AssignsAscendingIdsFromZero() public {
        _buy(alice);
        _buy(bob);
        _buy(alice);

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.nextTokenId(), 3);
    }

    // Invariant 1: the last allowed purchase
    function test_Mint_AllTenNftsCanBeSold() public {
        for (uint256 i = 0; i < 10; i++) {
            _buy(alice);
        }

        assertEq(nft.nextTokenId(), 10);
        assertEq(nft.balanceOf(alice), 10);
        assertEq(token.balanceOf(address(nft)), 10 * PRICE);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Mint_ContractReceiverCanBuy() public {
        ReceiverBuyer buyer = new ReceiverBuyer();
        token.mint(address(buyer), PRICE);

        buyer.buy(token, nft, PRICE);

        assertEq(nft.ownerOf(0), address(buyer));
        assertEq(token.balanceOf(address(buyer)), 0);
    }

    // --- withdraw ---

    // Invariant 6
    function test_Withdraw_SendsWholeBalanceToOwner() public {
        _buy(alice);
        _buy(bob);
        _buy(alice);

        uint256 contractBefore = token.balanceOf(address(nft));
        uint256 ownerBefore = token.balanceOf(owner);

        vm.prank(owner);
        nft.withdraw();

        assertEq(token.balanceOf(address(nft)), 0);
        assertEq(token.balanceOf(owner), ownerBefore + contractBefore);
    }

    // Trust assumption: tokens sent directly to the contract go to the owner
    function test_Withdraw_IncludesDirectTransfers() public {
        _buy(alice);

        vm.prank(bob);
        assertTrue(token.transfer(address(nft), 5 * 10 ** 18));

        vm.prank(owner);
        nft.withdraw();

        assertEq(token.balanceOf(owner), PRICE + 5 * 10 ** 18);
    }
}
