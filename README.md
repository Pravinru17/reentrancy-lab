# ReentrancyLab — Solidity Security

A security-focused Solidity project demonstrating a **classic reentrancy vulnerability**, a working exploit proof-of-concept, and the corresponding defenses using the **Checks-Effects-Interactions (CEI)** pattern and a `nonReentrant` guard.

The project is built with **Solidity 0.8.20** and tested using **Foundry**.

## Overview

The project is divided into two stages:

### Day 3 — Reentrancy Attack

A deliberately vulnerable `VulnerableBank` contract is exploited using a malicious `Attacker` contract.

The vulnerability occurs because the bank performs an external ETH transfer **before updating the user's balance**.

This allows the attacker's `receive()` function to call `withdraw()` again while the original transaction is still executing.

### Day 4 — Reentrancy Defense

The vulnerable implementation is fixed in `SecureBank` using:

* Checks-Effects-Interactions (CEI)
* `nonReentrant` protection
* State updates before external calls
* Reentrancy-focused tests

## Features

* Classic single-function reentrancy vulnerability
* Malicious attacker contract
* ETH callback through `receive()`
* Reentrancy exploit proof-of-concept
* Fuzz testing
* Checks-Effects-Interactions pattern
* Custom `nonReentrant` modifier
* Defense-in-depth approach
* Secure withdrawal implementation
* Attack regression tests
* Foundry-based testing
* Audit report documenting vulnerability and remediation

## Project Structure

```text
ReentrancyLab/
├── src/
│   ├── VulnerableBank.sol
│   ├── Attacker.sol
│   └── SecureBank.sol
│
├── test/
│   ├── ReentrancyTest.t.sol
│   └── SecureBankTest.t.sol
│
├── AUDIT.md
├── foundry.toml
├── lib/
└── README.md
```

# Day 3 — Reentrancy Attack

## Vulnerable Contract

`VulnerableBank.sol` contains a deliberately vulnerable withdrawal implementation.

The vulnerable flow is:

```text
Check balance
     ↓
Send ETH to msg.sender
     ↓
Attacker's receive() executes
     ↓
withdraw() called again
     ↓
Balance has NOT been updated
     ↓
ETH sent again
     ↓
Repeat
```

The critical issue is that the external call happens before the state update.

```solidity
function withdraw() external {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "No balance");

    // ❌ External call before state update
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");

    // ❌ State updated too late
    balances[msg.sender] = 0;
}
```

## Why Reentrancy Happens

When ETH is sent to a contract using:

```solidity
msg.sender.call{value: amount}("");
```

the recipient contract can execute its `receive()` function.

The attacker uses this callback to call `withdraw()` again before the original withdrawal has completed.

```text
Bank.withdraw()
      │
      │ send ETH
      ▼
Attacker.receive()
      │
      │ withdraw() again
      ▼
Bank.withdraw()
      │
      │ balance still exists
      ▼
Send ETH again
```

The attack continues until the configured limit is reached or the bank's ETH is exhausted.

## Attacker Contract

`Attacker.sol` contains the malicious callback:

```solidity
receive() external payable {
    callCount++;

    if (
        address(bank).balance >= attackAmount &&
        callCount < 10
    ) {
        bank.withdraw();
    }
}
```

The attacker first deposits ETH and then starts the withdrawal.

The withdrawal triggers `receive()`, which recursively calls `withdraw()`.

## Proof of Concept

The attack test demonstrates that an attacker can deposit a small amount and withdraw significantly more than their original deposit.

Example attack flow:

```text
Attacker deposits 1 ETH
        ↓
Attacker calls withdraw()
        ↓
Bank sends 1 ETH
        ↓
Attacker.receive()
        ↓
withdraw() again
        ↓
Bank sends another 1 ETH
        ↓
Repeat
        ↓
Bank funds drained
```

The test verifies:

* The attacker receives more than the original deposit
* The bank loses ETH
* Multiple withdrawal calls occur

## Example Result

```text
=== AFTER ATTACK ===

Bank balance: 0
Attacker balance: 11000000000000000000
Reentrancy calls made: 10

=== EXPLOIT SUCCESSFUL ===

Stolen: 10000000000000000000
```

The example demonstrates a complete drainage of the bank's 10 ETH balance after the attacker initially supplied 1 ETH.

# Day 4 — Reentrancy Defense

## Checks-Effects-Interactions

The first defense is the **Checks-Effects-Interactions (CEI)** pattern.

The correct order is:

```text
1. CHECKS
      ↓
2. EFFECTS
      ↓
3. INTERACTIONS
```

### Checks

Validate the user's balance and other conditions.

### Effects

Update contract state before making an external call.

### Interactions

Perform the external call only after state has been updated.

## Secure Withdrawal

The fixed withdrawal follows CEI:

```solidity
function withdraw() external nonReentrant {
    // 1. CHECKS
    uint256 amount = balances[msg.sender];
    require(amount > 0, "No balance");

    // 2. EFFECTS
    balances[msg.sender] = 0;
    totalDeposits -= amount;

    // 3. INTERACTIONS
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");

    emit Withdrawn(msg.sender, amount);
}
```

If the attacker attempts to re-enter after the balance has been cleared:

```text
balances[msg.sender] == 0
```

The second withdrawal fails.

## Reentrancy Guard

`SecureBank` also implements a `nonReentrant` modifier as an additional layer of protection.

```solidity
modifier nonReentrant() {
    require(
        _status != _ENTERED,
        "ReentrancyGuard: reentrant call"
    );

    _status = _ENTERED;

    _;

    _status = _NOT_ENTERED;
}
```

The contract uses two states:

```solidity
uint256 private constant _NOT_ENTERED = 1;
uint256 private constant _ENTERED = 2;
```

When `withdraw()` starts, the contract enters the `_ENTERED` state.

A reentrant call attempts to enter the function again while `_status == _ENTERED`, causing the call to revert.

## Defense in Depth

The project demonstrates two complementary defenses:

| Protection     | Purpose                                   | Limitation                                |
| -------------- | ----------------------------------------- | ----------------------------------------- |
| CEI            | Updates state before external interaction | Requires correct implementation           |
| `nonReentrant` | Blocks reentrant execution                | Does not replace correct state accounting |

Using both provides defense in depth.

# Testing

The project uses **Foundry / Forge** for testing.

## Vulnerability Tests

`ReentrancyTest.t.sol` verifies that:

* The vulnerable withdrawal can be re-entered
* The attacker performs multiple withdrawal calls
* The attacker receives more ETH than deposited
* The bank loses funds
* Normal users can still deposit and withdraw normally

## Fuzz Testing

The project also fuzzes the attack using different deposit amounts.

The fuzz test bounds the attack amount and verifies the attack behavior across generated inputs.

```solidity
depositAmount = bound(
    depositAmount,
    0.1 ether,
    5 ether
);
```

## Defense Tests

`SecureBankTest.t.sol` verifies that:

* Normal withdrawals still work
* User balances are cleared
* The malicious callback is triggered
* Reentrant withdrawal attempts are blocked
* The attacker cannot profit from repeated withdrawals

## Run Tests

Run the complete test suite:

```bash
forge test
```

Run with detailed traces:

```bash
forge test -vvvv
```

Run coverage:

```bash
forge coverage
```

## Expected Security Result

The vulnerable implementation should demonstrate a successful reentrancy attack.

The secure implementation should prevent the attacker from withdrawing the same balance multiple times.

```text
VulnerableBank
    ↓
Reentrancy succeeds
    ↓
Funds can be drained

SecureBank
    ↓
CEI + nonReentrant
    ↓
Reentrancy blocked
```

# Audit Report

The repository includes `AUDIT.md`, documenting:

* Vulnerability classification
* Vulnerable code
* Attack flow
* Proof of concept
* Impact
* Remediation
* CEI implementation
* Reentrancy guard
* Security recommendations
* Test results

## Vulnerability

**Reentrancy — Critical**

The root cause is the external ETH transfer occurring before the user's balance is updated.

### Impact

A successful attacker can repeatedly withdraw against the same recorded balance and potentially drain the contract's ETH.

The vulnerability affects funds belonging to other depositors as well.

# Security Recommendations

For production smart contracts:

* Follow the Checks-Effects-Interactions pattern
* Update accounting state before external calls
* Use a trusted reentrancy guard implementation
* Consider OpenZeppelin's `ReentrancyGuard`
* Consider pull-payment patterns for withdrawals
* Minimize unnecessary external calls
* Add regression tests for every discovered vulnerability
* Use static analysis tools such as Slither or Aderyn
* Perform independent security review before deployment

# Tools

* **Solidity:** `^0.8.20`
* **Foundry**
* **Forge**
* **Anvil**
* **Git**

# Learning Objectives

This project demonstrates practical understanding of:

* EVM call flow
* Solidity external calls
* ETH transfers
* `receive()` callbacks
* Single-function reentrancy
* Recursive contract execution
* Checks-Effects-Interactions
* Reentrancy guards
* State accounting
* Fuzz testing
* Security-focused testing
* Proof-of-concept exploit development
* Vulnerability remediation
* Security audit documentation

# Educational Disclaimer

`VulnerableBank.sol` is intentionally vulnerable and exists **only for security education and testing**.

It must not be deployed with real funds.

`SecureBank.sol` demonstrates the defensive techniques studied in this project but should still undergo comprehensive testing and professional security review before any production use.

# Author

**Pravin R**

Blockchain / Solidity Developer

GitHub: [Pravinru17](https://github.com/Pravinru17)

# License

MIT


```shell
$ forge --help
$ anvil --help
$ cast --help
```
