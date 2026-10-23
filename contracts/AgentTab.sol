// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract AgentTab is ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    struct Tab {
        address payer;
        address service;
        uint256 balance;
        uint256 redeemed;
        uint256 expiresAt;
        bool closed;
    }

    bytes32 private constant VOUCHER_TYPEHASH = keccak256("Voucher(bytes32 tabId,uint256 cumulativeAmount)");
    uint256 private constant GRACE_PERIOD = 1 hours;

    IERC20 public immutable token;

    mapping(bytes32 => Tab) internal _tabs;
    mapping(address => uint256) internal _nonces;
    mapping(address => uint256) public claimable;

    // Invariant: The contract's USDC balance must always equal sum of all open tab balances plus sum of all claimable balances.

    event TabOpened(
        bytes32 indexed tabId,
        address indexed payer,
        address indexed service,
        uint256 amount,
        uint256 expiresAt
    );
    event TabToppedUp(bytes32 indexed tabId, uint256 addedAmount, uint256 newBalance);
    event Redeemed(bytes32 indexed tabId, address indexed service, uint256 amount, uint256 newTotal);
    event TabClosed(bytes32 indexed tabId, address indexed payer, uint256 remaining);
    event PaymentCredited(address indexed recipient, uint256 amount);

    constructor(address _token) EIP712("AgentTab", "1") {
        require(_token != address(0), "token zero");
        token = IERC20(_token);
    }

    function openTab(address service, uint256 amount, uint256 expiresAt) external nonReentrant returns (bytes32 tabId) {
        require(service != address(0), "service zero");
        require(amount > 0, "amount zero");
        require(expiresAt > block.timestamp, "bad expiry");

        uint256 nonce = _nonces[msg.sender]++;
        tabId = keccak256(abi.encode(msg.sender, service, nonce));

        _tabs[tabId] = Tab({
            payer: msg.sender,
            service: service,
            balance: amount,
            redeemed: 0,
            expiresAt: expiresAt,
            closed: false
        });

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit TabOpened(tabId, msg.sender, service, amount, expiresAt);
    }

    function topUp(bytes32 tabId, uint256 amount) external nonReentrant {
        require(amount > 0, "amount zero");

        Tab storage tab = _tabs[tabId];
        require(tab.payer != address(0), "tab missing");
        require(!tab.closed, "tab closed");
        require(block.timestamp <= tab.expiresAt, "tab expired");

        tab.balance += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit TabToppedUp(tabId, amount, tab.balance);
    }

    function redeem(bytes32 tabId, uint256 cumulativeAmount, bytes calldata signature) external nonReentrant {
        Tab storage tab = _tabs[tabId];
        require(tab.payer != address(0), "tab missing");
        require(msg.sender == tab.service, "not service");
        require(!tab.closed, "tab closed");
        require(block.timestamp <= tab.expiresAt + GRACE_PERIOD, "grace ended");

        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, tabId, cumulativeAmount));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        require(signer == tab.payer, "bad sig");

        require(cumulativeAmount > tab.redeemed, "no new amount");

        uint256 toPay = cumulativeAmount - tab.redeemed;
        uint256 actual = toPay > tab.balance ? tab.balance : toPay;

        tab.balance -= actual;
        tab.redeemed += actual;

        if (!_tryTransfer(tab.service, actual)) {
            claimable[tab.service] += actual;
            emit PaymentCredited(tab.service, actual);
        }

        emit Redeemed(tabId, tab.service, actual, tab.redeemed);
    }

    function closeAfterExpiry(bytes32 tabId) external nonReentrant {
        Tab storage tab = _tabs[tabId];
        require(tab.payer != address(0), "tab missing");
        require(!tab.closed, "tab closed");
        require(block.timestamp > tab.expiresAt + GRACE_PERIOD, "grace active");

        uint256 remaining = tab.balance;
        tab.balance = 0;
        tab.closed = true;

        if (!_tryTransfer(tab.payer, remaining)) {
            claimable[tab.payer] += remaining;
            emit PaymentCredited(tab.payer, remaining);
        }

        emit TabClosed(tabId, tab.payer, remaining);
    }

    function withdraw() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "nothing claimable");

        claimable[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
    }

    function withdrawTo(address to) external nonReentrant {
        require(to != address(0), "to zero");

        uint256 amount = claimable[msg.sender];
        require(amount > 0, "nothing claimable");

        claimable[msg.sender] = 0;
        token.safeTransfer(to, amount);
    }

    function getTab(bytes32 tabId) external view returns (Tab memory) {
        return _tabs[tabId];
    }

    function _tryTransfer(address recipient, uint256 amount) internal returns (bool ok) {
        if (amount == 0) {
            return true;
        }
        // Guard: if the token contract has no code, treat the call as failed so funds
        // land in claimable rather than being silently lost.
        if (address(token).code.length == 0) {
            return false;
        }

        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount)
        );
        ok = success && (data.length == 0 || abi.decode(data, (bool)));
    }
}
