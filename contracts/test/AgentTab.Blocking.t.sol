// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTab} from "../AgentTab.sol";
import {MockBlockingToken} from "../test-helpers/MockBlockingToken.sol";

/// @dev Tests 10 & 11: MockBlockingToken, blocklist forces payments into claimable,
///      withdrawTo drains correctly, double-withdraw reverts, closeAfterExpiry with
///      blocked payer also lands in claimable.
contract AgentTabBlockingTest is Test {

    // ── EIP-712 constant (must match contract) ────────────────────────
    bytes32 internal constant VOUCHER_TYPEHASH =
        keccak256("Voucher(bytes32 tabId,uint256 cumulativeAmount)");

    // ── Actors ────────────────────────────────────────────────────────
    uint256 internal constant PAYER_PK = 0xA11CE;
    address internal payer;
    address internal service;
    address internal fresh;

    // ── Contracts ─────────────────────────────────────────────────────
    MockBlockingToken internal mbToken;
    AgentTab          internal aTab;

    uint256 internal constant AMOUNT = 1_000e6;
    uint256 internal expiry;

    function setUp() public {
        payer   = vm.addr(PAYER_PK);
        service = makeAddr("service");
        fresh   = makeAddr("fresh");

        mbToken = new MockBlockingToken();
        aTab    = new AgentTab(address(mbToken));

        expiry = block.timestamp + 1 days;

        // Fund payer and approve
        mbToken.mint(payer, 10_000e6);
        vm.prank(payer);
        mbToken.approve(address(aTab), type(uint256).max);
    }

    // ── Helpers ────────────────────────────────────────────────────────

    function _openTab() internal returns (bytes32 tabId) {
        vm.prank(payer);
        tabId = aTab.openTab(service, AMOUNT, expiry);
    }

    function _domainSeparator() internal view returns (bytes32) {
        (
            ,
            string memory name_,
            string memory version_,
            uint256 chainId_,
            address verifyingContract_,
            ,
        ) = aTab.eip712Domain();
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        return keccak256(abi.encode(
            typeHash,
            keccak256(bytes(name_)),
            keccak256(bytes(version_)),
            chainId_,
            verifyingContract_
        ));
    }

    function _signVoucher(bytes32 tabId, uint256 cumAmt)
        internal view
        returns (bytes memory sig)
    {
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, tabId, cumAmt));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PAYER_PK, digest);
        sig = abi.encodePacked(r, s, v);
    }

    // ══════════════════════════════════════════════════════════════════
    // Test 10a. redeem succeeds even when service is blocked
    // ══════════════════════════════════════════════════════════════════

    function test_Blocking_RedeemDoesNotRevertWhenServiceBlocked() public {
        bytes32 tabId = _openTab();
        mbToken.block_(service);

        bytes memory sig = _signVoucher(tabId, AMOUNT);

        // Must NOT revert
        vm.prank(service);
        aTab.redeem(tabId, AMOUNT, sig);
    }

    // ══════════════════════════════════════════════════════════════════
    // Test 10b. redeemed amount lands in claimable[service]
    // ══════════════════════════════════════════════════════════════════

    function test_Blocking_AmountLandsInClaimable() public {
        bytes32 tabId = _openTab();
        mbToken.block_(service);

        bytes memory sig = _signVoucher(tabId, AMOUNT);
        vm.prank(service);
        aTab.redeem(tabId, AMOUNT, sig);

        // service token balance must still be 0 (blocked)
        assertEq(mbToken.balanceOf(service), 0);
        // claimable must hold the full amount
        assertEq(aTab.claimable(service), AMOUNT);
    }

    // ══════════════════════════════════════════════════════════════════
    // Test 10c. withdrawTo(fresh) sends funds to fresh address
    // ══════════════════════════════════════════════════════════════════

    function test_Blocking_WithdrawToFreshAddress() public {
        bytes32 tabId = _openTab();
        mbToken.block_(service);

        bytes memory sig = _signVoucher(tabId, AMOUNT);
        vm.prank(service);
        aTab.redeem(tabId, AMOUNT, sig);

        // service is still blocked, but fresh is not
        uint256 freshBefore = mbToken.balanceOf(fresh);
        vm.prank(service);
        aTab.withdrawTo(fresh);

        assertEq(mbToken.balanceOf(fresh), freshBefore + AMOUNT);
        assertEq(aTab.claimable(service), 0);
    }

    // ══════════════════════════════════════════════════════════════════
    // Test 10d. second withdraw() reverts "nothing claimable"
    // ══════════════════════════════════════════════════════════════════

    function test_Blocking_DoubleWithdrawReverts() public {
        bytes32 tabId = _openTab();
        mbToken.block_(service);

        bytes memory sig = _signVoucher(tabId, AMOUNT);
        vm.prank(service);
        aTab.redeem(tabId, AMOUNT, sig);

        // First withdrawal (use withdrawTo fresh since service is blocked)
        vm.prank(service);
        aTab.withdrawTo(fresh);

        // Second withdrawal attempt, nothing left
        vm.prank(service);
        vm.expectRevert(bytes("nothing claimable"));
        aTab.withdrawTo(fresh);
    }

    // ══════════════════════════════════════════════════════════════════
    // Test 11. closeAfterExpiry with blocked payer → claimable[payer]
    // ══════════════════════════════════════════════════════════════════

    function test_Blocking_CloseWithBlockedPayer() public {
        bytes32 tabId = _openTab();

        // Block payer so the refund transfer fails
        mbToken.block_(payer);

        // Advance past expiry + grace
        vm.warp(expiry + 1 hours + 1);

        // Record payer balance before close, the refund must NOT add to it
        uint256 payerBalBefore = mbToken.balanceOf(payer);

        // Should not revert
        aTab.closeAfterExpiry(tabId);

        // Payer balance must be UNCHANGED (blocked, so no transfer went through)
        assertEq(mbToken.balanceOf(payer), payerBalBefore,
            "Blocked payer should not receive the direct transfer");
        // Refund must be in claimable instead
        assertEq(aTab.claimable(payer), AMOUNT,
            "Refund must land in claimable[payer] when payer is blocked");
    }

    // ── Extra: PaymentCredited event is emitted when blocked ──────────

    function test_Blocking_EmitsPaymentCreditedOnRedeem() public {
        bytes32 tabId = _openTab();
        mbToken.block_(service);

        bytes memory sig = _signVoucher(tabId, AMOUNT);

        vm.expectEmit(true, false, false, true, address(aTab));
        emit AgentTab.PaymentCredited(service, AMOUNT);

        vm.prank(service);
        aTab.redeem(tabId, AMOUNT, sig);
    }

    function test_Blocking_EmitsPaymentCreditedOnClose() public {
        bytes32 tabId = _openTab();
        mbToken.block_(payer);
        vm.warp(expiry + 1 hours + 1);

        vm.expectEmit(true, false, false, true, address(aTab));
        emit AgentTab.PaymentCredited(payer, AMOUNT);

        aTab.closeAfterExpiry(tabId);
    }
}
