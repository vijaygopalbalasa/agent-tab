// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentTab} from "../AgentTab.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockBlockingToken} from "../test-helpers/MockBlockingToken.sol";

/// @dev Shared setup, actors, and signing helpers for all AgentTab test categories.
abstract contract AgentTabTestBase is Test {

    // ── Actors ──────────────────────────────────────────────────────────────
    uint256 internal constant PAYER_PK  = 0xA11CE;
    address internal payer;          // vm.addr(PAYER_PK)
    address internal service;
    address internal stranger;

    // ── Contracts ────────────────────────────────────────────────────────────
    MockERC20  internal usdc;
    AgentTab   internal tab;

    // ── EIP-712 constants ────────────────────────────────────────────────────
    bytes32 internal constant VOUCHER_TYPEHASH =
        keccak256("Voucher(bytes32 tabId,uint256 cumulativeAmount)");

    // ── Tab parameters ───────────────────────────────────────────────────────
    uint256 internal constant INITIAL_AMOUNT = 1_000e6;   // 1 000 USDC
    uint256 internal expiry;

    // ────────────────────────────────────────────────────────────────────────
    function setUp() public virtual {
        payer    = vm.addr(PAYER_PK);
        service  = makeAddr("service");
        stranger = makeAddr("stranger");

        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        tab  = new AgentTab(address(usdc));

        expiry = block.timestamp + 1 days;

        // Fund payer with plenty of USDC and approve AgentTab
        usdc.mint(payer, 100_000e6);
        vm.prank(payer);
        usdc.approve(address(tab), type(uint256).max);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Opens a default tab (INITIAL_AMOUNT, expiry) from payer → service.
    function _openDefaultTab() internal returns (bytes32 tabId) {
        vm.prank(payer);
        tabId = tab.openTab(service, INITIAL_AMOUNT, expiry);
    }

    /// @dev Signs a voucher for (tabId, cumulativeAmount) with PAYER_PK.
    function _signVoucher(bytes32 tabId, uint256 cumulativeAmount)
        internal view
        returns (bytes memory sig)
    {
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, tabId, cumulativeAmount));
        bytes32 digest     = _buildDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PAYER_PK, digest);
        sig = abi.encodePacked(r, s, v);
    }

    /// @dev Reconstruct the EIP-712 digest from the contract's eip712Domain() values.
    function _buildDigest(bytes32 structHash) internal view returns (bytes32) {
        (
            ,             // fields
            string memory name_,
            string memory version_,
            uint256 chainId_,
            address verifyingContract_,
            ,             // salt
                          // extensions
        ) = tab.eip712Domain();

        bytes32 domainSep = _buildDomainSeparator(
            name_, version_, chainId_, verifyingContract_
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }

    function _buildDomainSeparator(
        string memory name_,
        string memory version_,
        uint256 chainId_,
        address verifyingContract_
    ) internal pure returns (bytes32) {
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
