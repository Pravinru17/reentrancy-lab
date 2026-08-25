// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VulnerableBank {
    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "Must deposit something");

        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    // VULNERABLE: external call happens before state update
    function withdraw() external {
        uint256 amount = balances[msg.sender];

        require(amount > 0, "No balance");

        // BUG: external call first
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        // BUG: state updated too late
        balances[msg.sender] = 0;

        emit Withdrawn(msg.sender, amount);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}