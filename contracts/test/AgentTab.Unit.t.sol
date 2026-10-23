// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentTabTestBase} from "./AgentTab.Base.t.sol";
import {AgentTab} from "../AgentTab.sol";

/// @dev Unit tests covering: deployment, openTab, topUp, redeem (happy + reverts),
///      closeAfterExpiry, getTab, and the EIP-712 signing cases.
contract AgentTabUnitTest is AgentTabTestBase {

    // ══════════════════════════════════════════════════════════════════
    // 1. Deployment & initialization
    // ══════════════════════════════════════════════════════════════════

    function test_Deploy_TokenStored() public view {
        assertEq(address(tab.token()), address(usdc));
    }

    function test_Deploy_RejectsZeroToken() public {
        vm.expectRevert(bytes("token zero"));
        new AgentTab(address(0));
    }

    // ══════════════════════════════════════════════════════════════════
    // 2. openTab happy path / events
    // ══════════════════════════════════════════════════════════════════

    function test_OpenTab_StoresTab() public {
        bytes32 tabId = _openDefaultTab();
        AgentTab.Tab memory t = tab.getTab(tabId);

        assertEq(t.payer,    payer);
        assertEq(t.service,  service);
        assertEq(t.balance,  INITIAL_AMOUNT);
        assertEq(t.redeemed, 0);
        assertEq(t.expiresAt, expiry);
        assertFalse(t.closed);
    }

    function test_OpenTab_TransfersUSDCToContract() public {
        uint256 before = usdc.balanceOf(address(tab));
        _openDefaultTab();
        assertEq(usdc.balanceOf(address(tab)), before + INITIAL_AMOUNT);
    }

    function test_OpenTab_EmitsTabOpened() public {
        // We need to predict the tabId: nonce starts at 0.
        bytes32 expectedId = keccak256(abi.encode(payer, service, uint256(0)));

        vm.expectEmit(true, true, true, true, address(tab));
        emit AgentTab.TabOpened(expectedId, payer, service, INITIAL_AMOUNT, expiry);

        vm.prank(payer);
        tab.openTab(service, INITIAL_AMOUNT, expiry);
    }

    function test_OpenTab_RevertServiceZero() public {
        vm.prank(payer);
        vm.expectRevert(bytes("service zero"));
        tab.openTab(address(0), INITIAL_AMOUNT, expiry);
    }

    function test_OpenTab_RevertAmountZero() public {
        vm.prank(payer);
        vm.expectRevert(bytes("amount zero"));
        tab.openTab(service, 0, expiry);
    }

    function test_OpenTab_RevertBadExpiry() public {
        vm.prank(payer);
        vm.expectRevert(bytes("bad expiry"));
        tab.openTab(service, INITIAL_AMOUNT, block.timestamp);
    }

    // ══════════════════════════════════════════════════════════════════
    // 13. getTab view
    // ══════════════════════════════════════════════════════════════════

    function test_GetTab_ReturnsDefaultForUnknown() public view {
        AgentTab.Tab memory t = tab.getTab(bytes32(0));
        assertEq(t.payer, address(0));
    }

    // ══════════════════════════════════════════════════════════════════
    // 12. topUp
    // ══════════════════════════════════════════════════════════════════

    function test_TopUp_IncreasesBalance() public {
        bytes32 tabId = _openDefaultTab();
        uint256 topUpAmt = 500e6;

        usdc.mint(payer, topUpAmt);
        vm.prank(payer);
        tab.topUp(tabId, topUpAmt);

        AgentTab.Tab memory t = tab.getTab(tabId);
        assertEq(t.balance, INITIAL_AMOUNT + topUpAmt);
    }

    function test_TopUp_EmitsTabToppedUp() public {
        bytes32 tabId = _openDefaultTab();
        uint256 topUpAmt = 200e6;

        usdc.mint(payer, topUpAmt);
        vm.expectEmit(true, false, false, true, address(tab));
        emit AgentTab.TabToppedUp(tabId, topUpAmt, INITIAL_AMOUNT + topUpAmt);

        vm.prank(payer);
        tab.topUp(tabId, topUpAmt);
    }

    function test_TopUp_RevertAfterExpiry() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1);

        usdc.mint(payer, 100e6);
        vm.prank(payer);
        vm.expectRevert(bytes("tab expired"));
        tab.topUp(tabId, 100e6);
    }

    function test_TopUp_RevertAmountZero() public {
        bytes32 tabId = _openDefaultTab();
        vm.expectRevert(bytes("amount zero"));
        tab.topUp(tabId, 0);
    }

    function test_TopUp_RevertTabMissing() public {
        vm.expectRevert(bytes("tab missing"));
        tab.topUp(bytes32(uint256(999)), 100e6);
    }

    // ══════════════════════════════════════════════════════════════════
    // 1 (from spec). Redeem, pays exactly the new amount
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_PaysExactDifference() public {
        bytes32 tabId = _openDefaultTab();
        uint256 cumAmt = 300e6;
        bytes memory sig = _signVoucher(tabId, cumAmt);

        uint256 serviceBefore = usdc.balanceOf(service);

        vm.prank(service);
        tab.redeem(tabId, cumAmt, sig);

        assertEq(usdc.balanceOf(service), serviceBefore + cumAmt);

        AgentTab.Tab memory t = tab.getTab(tabId);
        assertEq(t.redeemed, cumAmt);
        assertEq(t.balance,  INITIAL_AMOUNT - cumAmt);
    }

    function test_Redeem_EmitsRedeemed() public {
        bytes32 tabId = _openDefaultTab();
        uint256 cumAmt = 100e6;
        bytes memory sig = _signVoucher(tabId, cumAmt);

        vm.expectEmit(true, true, false, true, address(tab));
        emit AgentTab.Redeemed(tabId, service, cumAmt, cumAmt);

        vm.prank(service);
        tab.redeem(tabId, cumAmt, sig);
    }

    // ══════════════════════════════════════════════════════════════════
    // 2 (from spec). Replay same cumulativeAmount → "no new amount"
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_ReplayReverts() public {
        bytes32 tabId = _openDefaultTab();
        uint256 cumAmt = 100e6;
        bytes memory sig = _signVoucher(tabId, cumAmt);

        vm.prank(service);
        tab.redeem(tabId, cumAmt, sig);

        // Re-sign with same cumulative amount
        bytes memory sig2 = _signVoucher(tabId, cumAmt);
        vm.prank(service);
        vm.expectRevert(bytes("no new amount"));
        tab.redeem(tabId, cumAmt, sig2);
    }

    // ══════════════════════════════════════════════════════════════════
    // 3 (from spec). Wrong signer → "bad sig"
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_WrongSignerReverts() public {
        bytes32 tabId = _openDefaultTab();
        uint256 cumAmt = 100e6;

        // Sign with a different private key (stranger)
        uint256 strangerPk = 0xBAD;
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, tabId, cumAmt));
        bytes32 digest = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(service);
        vm.expectRevert(bytes("bad sig"));
        tab.redeem(tabId, cumAmt, badSig);
    }

    // ══════════════════════════════════════════════════════════════════
    // 4 (from spec). Voucher signed for a different tabId → "bad sig"
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_WrongTabIdReverts() public {
        bytes32 tabId = _openDefaultTab();

        // Open a second tab to get a different tabId
        vm.prank(payer);
        bytes32 otherTabId = tab.openTab(service, INITIAL_AMOUNT, expiry);

        uint256 cumAmt = 100e6;
        // Sign the voucher for the OTHER tabId
        bytes memory sig = _signVoucher(otherTabId, cumAmt);

        vm.prank(service);
        vm.expectRevert(bytes("bad sig"));
        tab.redeem(tabId, cumAmt, sig);
    }

    // ══════════════════════════════════════════════════════════════════
    // 5 (from spec). cumulativeAmount > balance → pays only balance
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_CapsAtBalance() public {
        bytes32 tabId = _openDefaultTab();
        uint256 overAmt = INITIAL_AMOUNT * 2;   // more than funded
        bytes memory sig = _signVoucher(tabId, overAmt);

        uint256 serviceBefore = usdc.balanceOf(service);

        vm.prank(service);
        tab.redeem(tabId, overAmt, sig);

        // Service should receive exactly INITIAL_AMOUNT (the tab's balance)
        assertEq(usdc.balanceOf(service), serviceBefore + INITIAL_AMOUNT);

        AgentTab.Tab memory t = tab.getTab(tabId);
        assertEq(t.balance,  0);
        assertEq(t.redeemed, INITIAL_AMOUNT);
    }

    // ══════════════════════════════════════════════════════════════════
    // 6 (from spec). Only service can redeem
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_NonServiceReverts() public {
        bytes32 tabId = _openDefaultTab();
        bytes memory sig = _signVoucher(tabId, 100e6);

        vm.prank(stranger);
        vm.expectRevert(bytes("not service"));
        tab.redeem(tabId, 100e6, sig);
    }

    // ══════════════════════════════════════════════════════════════════
    // 7 (from spec). closeAfterExpiry before grace period ends → "grace active"
    // ══════════════════════════════════════════════════════════════════

    function test_Close_BeforeGraceReverts() public {
        bytes32 tabId = _openDefaultTab();

        // Warp to expiry, still inside grace period
        vm.warp(expiry + 1 hours - 1);
        vm.expectRevert(bytes("grace active"));
        tab.closeAfterExpiry(tabId);
    }

    function test_Close_AfterGraceSucceeds() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1 hours + 1);

        uint256 payerBefore = usdc.balanceOf(payer);
        tab.closeAfterExpiry(tabId);

        assertEq(usdc.balanceOf(payer), payerBefore + INITIAL_AMOUNT);

        AgentTab.Tab memory t = tab.getTab(tabId);
        assertTrue(t.closed);
        assertEq(t.balance, 0);
    }

    function test_Close_EmitsTabClosed() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1 hours + 1);

        vm.expectEmit(true, true, false, true, address(tab));
        emit AgentTab.TabClosed(tabId, payer, INITIAL_AMOUNT);

        tab.closeAfterExpiry(tabId);
    }

    // ══════════════════════════════════════════════════════════════════
    // 8 (from spec). Redeem after close → "tab closed"
    // ══════════════════════════════════════════════════════════════════

    function test_Redeem_AfterCloseReverts() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1 hours + 1);
        tab.closeAfterExpiry(tabId);

        bytes memory sig = _signVoucher(tabId, 100e6);
        vm.prank(service);
        vm.expectRevert(bytes("tab closed"));
        tab.redeem(tabId, 100e6, sig);
    }

    function test_Close_AlreadyClosedReverts() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1 hours + 1);
        tab.closeAfterExpiry(tabId);

        vm.expectRevert(bytes("tab closed"));
        tab.closeAfterExpiry(tabId);
    }

    // ══════════════════════════════════════════════════════════════════
    // withdraw / withdrawTo basics
    // ══════════════════════════════════════════════════════════════════

    function test_Withdraw_NothingClaimableReverts() public {
        vm.prank(service);
        vm.expectRevert(bytes("nothing claimable"));
        tab.withdraw();
    }

    function test_WithdrawTo_ZeroAddressReverts() public {
        vm.prank(service);
        vm.expectRevert(bytes("to zero"));
        tab.withdrawTo(address(0));
    }

    function test_WithdrawTo_NothingClaimableReverts() public {
        vm.prank(service);
        vm.expectRevert(bytes("nothing claimable"));
        tab.withdrawTo(stranger);
    }

    // Redeem past grace period → "grace ended"
    function test_Redeem_AfterGraceEnded() public {
        bytes32 tabId = _openDefaultTab();
        vm.warp(expiry + 1 hours + 1);

        bytes memory sig = _signVoucher(tabId, 100e6);
        vm.prank(service);
        vm.expectRevert(bytes("grace ended"));
        tab.redeem(tabId, 100e6, sig);
    }

    // Redeem on tab that doesn't exist → "tab missing"
    function test_Redeem_TabMissingReverts() public {
        bytes memory sig = _signVoucher(bytes32(uint256(999)), 100e6);
        vm.prank(service);
        vm.expectRevert(bytes("tab missing"));
        tab.redeem(bytes32(uint256(999)), 100e6, sig);
    }
}
