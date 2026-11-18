// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20Errors, IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

/// Contract buyer without `onERC721Received`, so `_safeMint` must reject it.
contract NonReceiverBuyer {
    function buy(PaymentToken token, PurchasableNFT nft, uint256 price) external {
        token.approve(address(nft), price);
        nft.mint();
    }
}

/// Attacker: re-enters `mint()` from the `_safeMint` callback until all NFTs are sold.
contract ReentrantBuyer is IERC721Receiver {
    PurchasableNFT internal immutable nft;

    constructor(PurchasableNFT nft_) {
        nft = nft_;
    }

    function attack(PaymentToken token) external {
        token.approve(address(nft), type(uint256).max);
        nft.mint();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (nft.nextTokenId() < nft.MAX_SUPPLY()) {
            nft.mint();
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract PurchasableNFTTest is Test {
    PaymentToken internal token;
    PurchasableNFT internal nft;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol"); // starts without tokens

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

    // --- failure cases ---

    function test_RevertWhen_ConstructorGetsZeroAddress() public {
        vm.expectRevert(PurchasableNFT.ZeroAddress.selector);
        new PurchasableNFT(address(0));
    }

    // Invariant 1
    function test_RevertWhen_MintAfterSoldOut() public {
        for (uint256 i = 0; i < 10; i++) {
            _buy(alice);
        }

        // approve first: expectRevert only applies to the next call
        vm.startPrank(bob);
        token.approve(address(nft), PRICE);
        vm.expectRevert(PurchasableNFT.SoldOut.selector);
        nft.mint();
        vm.stopPrank();

        assertEq(nft.nextTokenId(), 10);
        assertEq(token.balanceOf(bob), START_BALANCE);
    }

    // Invariant 5
    function test_RevertWhen_MintWithoutApproval() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), 0, PRICE)
        );
        nft.mint();

        assertEq(nft.nextTokenId(), 0);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(token.balanceOf(alice), START_BALANCE);
    }

    // Invariant 5
    function test_RevertWhen_MintWithoutBalance() public {
        vm.startPrank(carol);
        token.approve(address(nft), PRICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, PRICE));
        nft.mint();
        vm.stopPrank();

        assertEq(nft.nextTokenId(), 0);
        assertEq(nft.balanceOf(carol), 0);
    }

    // Invariant 5: the payment made before _safeMint is rolled back as well
    function test_RevertWhen_ContractCannotReceiveNft() public {
        NonReceiverBuyer buyer = new NonReceiverBuyer();
        token.mint(address(buyer), PRICE);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(buyer)));
        buyer.buy(token, nft, PRICE);

        assertEq(nft.nextTokenId(), 0);
        assertEq(token.balanceOf(address(buyer)), PRICE);
        assertEq(token.balanceOf(address(nft)), 0);
    }

    // Invariant 7
    function test_RevertWhen_StrangerWithdraws() public {
        _buy(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.withdraw();

        assertEq(token.balanceOf(address(nft)), PRICE);
    }

    function test_RevertWhen_WithdrawWithZeroBalance() public {
        vm.prank(owner);
        vm.expectRevert(PurchasableNFT.NothingToWithdraw.selector);
        nft.withdraw();
    }

    // Invariant 8
    function test_RevertWhen_OwnerRenouncesOwnership() public {
        vm.prank(owner);
        vm.expectRevert(PurchasableNFT.RenounceOwnershipDisabled.selector);
        nft.renounceOwnership();

        assertEq(nft.owner(), owner);
    }

    // Invariant 8, enforced by OpenZeppelin
    function test_RevertWhen_TransferOwnershipToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        nft.transferOwnership(address(0));

        assertEq(nft.owner(), owner);
    }

    // --- attack ---

    // Threat: reentrancy through the _safeMint callback. Every re-entry pays, and the cap holds.
    function test_Reentrancy_EachReentryPaysAndCapHolds() public {
        ReentrantBuyer attacker = new ReentrantBuyer(nft);
        token.mint(address(attacker), 20 * PRICE);

        attacker.attack(token);

        assertEq(nft.nextTokenId(), 10);
        assertEq(nft.balanceOf(address(attacker)), 10);
        assertEq(token.balanceOf(address(attacker)), 10 * PRICE);
        assertEq(token.balanceOf(address(nft)), 10 * PRICE);
    }

    // --- fuzz ---

    // Invariant 2
    function testFuzz_Mint_MovesExactlyPrice(uint256 startBalance) public {
        startBalance = bound(startBalance, PRICE, 1e30);
        token.mint(carol, startBalance);

        _buy(carol);

        assertEq(token.balanceOf(carol), startBalance - PRICE);
        assertEq(token.balanceOf(address(nft)), PRICE);
    }

    // Invariant 1
    function testFuzz_SupplyNeverExceedsMax(uint256 attempts) public {
        attempts = bound(attempts, 0, 25);
        token.mint(alice, 25 * PRICE);

        vm.startPrank(alice);
        for (uint256 i = 0; i < attempts; i++) {
            token.approve(address(nft), PRICE);
            if (i >= 10) vm.expectRevert(PurchasableNFT.SoldOut.selector);
            nft.mint();
        }
        vm.stopPrank();

        uint256 expected = attempts < 10 ? attempts : 10;
        assertEq(nft.nextTokenId(), expected);
        assertEq(nft.balanceOf(alice), expected);
        assertLe(nft.nextTokenId(), 10);
    }

    // Invariant 5
    function testFuzz_RevertWhen_AllowanceBelowPrice(uint256 allowance) public {
        allowance = bound(allowance, 0, PRICE - 1);

        vm.startPrank(alice);
        token.approve(address(nft), allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), allowance, PRICE)
        );
        nft.mint();
        vm.stopPrank();

        assertEq(nft.nextTokenId(), 0);
        assertEq(token.balanceOf(alice), START_BALANCE);
    }

    // Invariant 7
    function testFuzz_RevertWhen_NonOwnerWithdraws(address caller) public {
        vm.assume(caller != owner);
        _buy(alice);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        nft.withdraw();

        assertEq(token.balanceOf(address(nft)), PRICE);
    }

    // Invariant 6
    function testFuzz_Withdraw_SendsExactBalance(uint256 purchases, uint256 donation) public {
        purchases = bound(purchases, 1, 10);
        donation = bound(donation, 0, 1e24);

        for (uint256 i = 0; i < purchases; i++) {
            _buy(alice);
        }
        token.mint(address(nft), donation);

        uint256 ownerBefore = token.balanceOf(owner);
        vm.prank(owner);
        nft.withdraw();

        assertEq(token.balanceOf(owner), ownerBefore + purchases * PRICE + donation);
        assertEq(token.balanceOf(address(nft)), 0);
    }

    // Invariant 8
    function testFuzz_RevertWhen_AnyoneRenouncesOwnership(address caller) public {
        vm.prank(caller);
        vm.expectRevert(PurchasableNFT.RenounceOwnershipDisabled.selector);
        nft.renounceOwnership();

        assertEq(nft.owner(), owner);
    }
}
