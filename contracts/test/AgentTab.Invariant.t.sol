// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTab} from "../AgentTab.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Handler for the invariant fuzzer.
// It drives openTab, topUp, redeem, and closeAfterExpiry with bounded inputs
// while maintaining ghost-accounting that mirrors what the invariant checks.
// ─────────────────────────────────────────────────────────────────────────────
contract AgentTabHandler is Test {

    bytes32 internal constant VOUCHER_TYPEHASH =
        keccak256("Voucher(bytes32 tabId,uint256 cumulativeAmount)");

    AgentTab  public  aTab;
    MockERC20 public  usdc;

    // Known tabs & their payer keys (so we can sign vouchers)
    bytes32[] public  tabIds;
    uint256[] public  payerKeys;

    // Ghost sums, updated by the handler in lock-step with real state
    uint256 public ghostTotalTabBalances;
    uint256 public ghostTotalClaimable;

    // Per-tab ghost: cumulative amount last redeemed (mirrors tab.redeemed)
    mapping(bytes32 => uint256) public ghostRedeemed;

    constructor(AgentTab _tab, MockERC20 _usdc) {
        aTab = _tab;
        usdc = _usdc;
    }

    // ── openTab ────────────────────────────────────────────────────────────

    function openTab(uint256 pkSeed, uint256 amount, uint256 duration) external {
        uint256 pk = bound(pkSeed, 1, type(uint128).max);
        address payerAddr = vm.addr(pk);
        amount  = bound(amount,   1e6,   10_000e6);
        duration = bound(duration, 1,    7 days);

        address svcAddr = makeAddr("handler_service");
        uint256 exp     = block.timestamp + duration;

        // Fund + approve
        usdc.mint(payerAddr, amount);
        vm.prank(payerAddr);
        usdc.approve(address(aTab), amount);

        vm.prank(payerAddr);
        bytes32 tabId = aTab.openTab(svcAddr, amount, exp);

        tabIds.push(tabId);
        payerKeys.push(pk);
        ghostTotalTabBalances += amount;
    }

    // ── topUp ──────────────────────────────────────────────────────────────

    function topUp(uint256 idx, uint256 amount) external {
        if (tabIds.length == 0) return;
        idx = bound(idx, 0, tabIds.length - 1);
        bytes32 tabId = tabIds[idx];

        AgentTab.Tab memory t = aTab.getTab(tabId);
        if (t.closed) return;
        if (block.timestamp > t.expiresAt) return;

        amount = bound(amount, 1e6, 5_000e6);
        address payerAddr = t.payer;

        usdc.mint(payerAddr, amount);
        vm.prank(payerAddr);
        usdc.approve(address(aTab), amount);

        vm.prank(payerAddr);
        aTab.topUp(tabId, amount);

        ghostTotalTabBalances += amount;
    }

    // ── redeem ─────────────────────────────────────────────────────────────

    function redeem(uint256 idx, uint256 incrementSeed) external {
        if (tabIds.length == 0) return;
        idx = bound(idx, 0, tabIds.length - 1);
        bytes32 tabId = tabIds[idx];

        AgentTab.Tab memory t = aTab.getTab(tabId);
        if (t.closed) return;
        if (block.timestamp > t.expiresAt + 1 hours) return;
        if (t.balance == 0) return;

        // Increment on top of current cumulative to produce a new cumulative
        uint256 increment = bound(incrementSeed, 1, t.balance);
        uint256 cumAmt    = t.redeemed + increment;

        // Sign the voucher
        uint256 pk = payerKeys[idx];
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, tabId, cumAmt));
        bytes32 domSep = _domainSeparator();
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domSep, structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 actualPay = cumAmt - t.redeemed;
        if (actualPay > t.balance) actualPay = t.balance;

        vm.prank(t.service);
        aTab.redeem(tabId, cumAmt, sig);

        ghostTotalTabBalances -= actualPay;
        // If transfer succeeded, claimable unchanged; if failed (no blocklist here), same
        // We use a plain ERC20 here so transfer always succeeds, claimable stays 0
    }

    // ── closeAfterExpiry ───────────────────────────────────────────────────

    function close(uint256 idx) external {
        if (tabIds.length == 0) return;
        idx = bound(idx, 0, tabIds.length - 1);
        bytes32 tabId = tabIds[idx];

        AgentTab.Tab memory t = aTab.getTab(tabId);
        if (t.closed) return;
        if (block.timestamp <= t.expiresAt + 1 hours) return;

        uint256 remaining = t.balance;

        aTab.closeAfterExpiry(tabId);

        ghostTotalTabBalances -= remaining;
    }

    // ── time advancement (so the fuzzer can age tabs) ─────────────────────

    function warpForward(uint256 secs) external {
        secs = bound(secs, 0, 2 days);
        vm.warp(block.timestamp + secs);
    }

    function tabCount() external view returns (uint256) {
        return tabIds.length;
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant test contract
// ─────────────────────────────────────────────────────────────────────────────
contract AgentTabInvariantTest is Test {

    AgentTab        internal aTab;
    MockERC20       internal usdc;
    AgentTabHandler internal handler;

    function setUp() public {
        usdc    = new MockERC20("Mock USDC", "mUSDC", 6);
        aTab    = new AgentTab(address(usdc));
        handler = new AgentTabHandler(aTab, usdc);

        targetContract(address(handler));
    }

    // ─────────────────────────────────────────────────────────────────────
    // INVARIANT 9: contract's USDC balance == Σ open tab balances + Σ claimable
    //
    // We verify this against the handler's ghost accounting rather than
    // iterating all possible tabs (which would require an enumerate-all approach).
    // The handler's ghost mirrors the on-chain sums exactly for the tabs it touched.
    // ─────────────────────────────────────────────────────────────────────

    function invariant_ContractBalanceEqualsGhostSum() public view {
        uint256 contractBal = usdc.balanceOf(address(aTab));
        uint256 ghostSum    = handler.ghostTotalTabBalances() + handler.ghostTotalClaimable();
        assertEq(contractBal, ghostSum,
            "Contract USDC balance must equal sum of tab balances + claimable");
    }

    // Secondary: contract holds at least ghost tab balances (sanity)
    function invariant_ContractBalanceGteTabBalances() public view {
        assertGe(
            usdc.balanceOf(address(aTab)),
            handler.ghostTotalTabBalances(),
            "Contract balance must cover all open tab balances"
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fuzz test (property-based, single-sequence)
// ─────────────────────────────────────────────────────────────────────────────
contract AgentTabFuzzTest is Test {

    bytes32 internal constant VOUCHER_TYPEHASH =
        keccak256("Voucher(bytes32 tabId,uint256 cumulativeAmount)");

    uint256 internal constant PAYER_PK = 0xA11CE;
    address internal payer;
    address internal service;
    MockERC20 internal usdc;
    AgentTab  internal aTab;

    uint256 internal expiry;

    function setUp() public {
        payer   = vm.addr(PAYER_PK);
        service = makeAddr("service");

        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        aTab = new AgentTab(address(usdc));

        expiry = block.timestamp + 1 days;

        usdc.mint(payer, 100_000e6);
        vm.prank(payer);
        usdc.approve(address(aTab), type(uint256).max);
    }

    // ── Fuzz: paying exactly the incremental difference ────────────────────

    function testFuzz_RedeemPaysExactIncrement(
        uint256 firstAmt,
        uint256 secondAmt
    ) public {
        firstAmt  = bound(firstAmt,  1,  INITIAL_AMOUNT() / 2);
        secondAmt = bound(secondAmt, firstAmt + 1, INITIAL_AMOUNT());

        // Open tab
        vm.prank(payer);
        bytes32 tabId = aTab.openTab(service, INITIAL_AMOUNT(), expiry);

        // First redeem
        bytes memory sig1 = _signVoucher(tabId, firstAmt);
        vm.prank(service);
        aTab.redeem(tabId, firstAmt, sig1);

        uint256 balAfterFirst = usdc.balanceOf(service);

        // Second redeem with higher cumulative
        bytes memory sig2 = _signVoucher(tabId, secondAmt);
        vm.prank(service);
        aTab.redeem(tabId, secondAmt, sig2);

        uint256 expectedIncrement = secondAmt - firstAmt;
        assertEq(
            usdc.balanceOf(service),
            balAfterFirst + expectedIncrement,
            "Second redeem must pay only the increment"
        );
    }

    // ── Fuzz: balance conservation across a redeem sequence ───────────────

    function testFuzz_BalanceConservation(uint256 fundAmt, uint256 redeemAmt) public {
        fundAmt   = bound(fundAmt,   1e6,  50_000e6);
        redeemAmt = bound(redeemAmt, 0,    fundAmt);

        vm.prank(payer);
        bytes32 tabId = aTab.openTab(service, fundAmt, expiry);

        bytes memory sig = _signVoucher(tabId, redeemAmt);

        uint256 contractBefore = usdc.balanceOf(address(aTab));

        if (redeemAmt == 0) {
            // redeemAmt == 0 would hit "no new amount" since redeemed starts at 0
            // This validates the boundary, no revert expected if we skip it
            return;
        }

        vm.prank(service);
        aTab.redeem(tabId, redeemAmt, sig);

        uint256 actual = redeemAmt <= fundAmt ? redeemAmt : fundAmt;

        // Contract balance decreased by the amount paid out
        assertEq(
            usdc.balanceOf(address(aTab)),
            contractBefore - actual,
            "Contract balance must decrease by paid amount"
        );
    }

    // ── Fuzz: topUp increases tab balance by exactly the topped-up amount ──

    function testFuzz_TopUpIncreasesBalance(uint256 topUpAmt) public {
        topUpAmt = bound(topUpAmt, 1, 10_000e6);

        vm.prank(payer);
        bytes32 tabId = aTab.openTab(service, INITIAL_AMOUNT(), expiry);

        usdc.mint(payer, topUpAmt);
        vm.prank(payer);
        aTab.topUp(tabId, topUpAmt);

        AgentTab.Tab memory t = aTab.getTab(tabId);
        assertEq(t.balance, INITIAL_AMOUNT() + topUpAmt);
    }

    function INITIAL_AMOUNT() internal pure returns (uint256) {
        return 1_000e6;
    }

    function _fuzzDomainSeparator() internal view returns (bytes32) {
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
            abi.encodePacked("\x19\x01", _fuzzDomainSeparator(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PAYER_PK, digest);
        sig = abi.encodePacked(r, s, v);
    }
}
