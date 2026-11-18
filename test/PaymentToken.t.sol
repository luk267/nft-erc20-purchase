// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PaymentToken} from "../src/PaymentToken.sol";

contract PaymentTokenTest is Test {
    PaymentToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new PaymentToken();
    }

    function test_Metadata() public view {
        assertEq(token.name(), "PaymentToken");
        assertEq(token.symbol(), "PAY");
        assertEq(token.decimals(), 18);
    }

    function test_Mint_AnyoneCanMint() public {
        vm.prank(alice);
        token.mint(bob, 50 * 10 ** 18);

        assertEq(token.balanceOf(bob), 50 * 10 ** 18);
        assertEq(token.totalSupply(), 50 * 10 ** 18);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.mint(address(0), 1);
    }
}
