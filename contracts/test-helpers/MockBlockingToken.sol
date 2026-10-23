// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev ERC-20 mock with a blocklist. transfer/transferFrom to a blocked address
///      returns false (simulating USDC's blocklist). No revert, just false, which
///      is enough for SafeERC20 to detect failure via _tryTransfer.
contract MockBlockingToken {
    string public name     = "Mock Blocking USDC";
    string public symbol   = "mbUSDC";
    uint8  public decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public blocked;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function block_(address addr) external {
        blocked[addr] = true;
    }

    function unblock(address addr) external {
        blocked[addr] = false;
    }

    function mint(address to, uint256 amount) external {
        totalSupply        += amount;
        balanceOf[to]      += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (blocked[to]) return false;
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (blocked[to]) return false;
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC20: allowance exceeded");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
