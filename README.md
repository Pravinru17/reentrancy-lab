# ReentrancyLab — Solidity Security

A security-focused Solidity project demonstrating a classic **single-function reentrancy vulnerability**, a working proof-of-concept exploit, and defensive remediation using the **Checks-Effects-Interactions (CEI)** pattern and a custom `nonReentrant` guard.

Built with **Solidity 0.8.20** and tested using **Foundry**.

> **Educational security lab:** `VulnerableBank.sol` is intentionally vulnerable and must not be used with real funds.

---

# Overview

The project demonstrates the complete smart-contract security workflow:

```text
Vulnerable Contract
        ↓
Identify Reentrancy
        ↓
Build Exploit Contract
        ↓
Write Proof-of-Concept Test
        ↓
Implement Fix
        ↓
Test the Fix
        ↓
Document the Vulnerability
```

The repository contains two versions of the bank:

### VulnerableBank

Intentionally contains a reentrancy vulnerability caused by performing an external ETH transfer **before updating the user's balance**.

### SecureBank

Demonstrates the remediation using:

- Checks-Effects-Interactions
- State update before external interaction
- `nonReentrant` protection
- Security regression tests

---

# Security Concepts Demonstrated

- Single-function reentrancy
- External contract calls
- ETH transfer callbacks
- `receive()` functions
- Recursive contract execution
- Checks-Effects-Interactions
- Reentrancy guards
- State accounting
- Foundry testing
- Fuzz testing
- Proof-of-concept exploit development
- Security regression testing
- Vulnerability documentation

---

# Project Structure

```text
reentrancy-lab/
│
├── src/
│   ├── VulnerableBank.sol
│   ├── Attacker.sol
│   └── SecureBank.sol
│
├── test/
│   ├── ReentrancyTest.t.sol
│   └── SecureBankAttacker.t.sol
│
├── AUDIT.md
├── foundry.toml
├── lib/
└── README.md
```

---

# Vulnerable Contract

`VulnerableBank.sol` contains the intentionally vulnerable withdrawal function.

The vulnerable logic follows this pattern:

```solidity
function withdraw() external {
    uint256 amount = balances[msg.sender];

    require(amount > 0, "No balance");

    // External interaction
    (bool success, ) =
        msg.sender.call{value: amount}("");

    require(success, "Transfer failed");

    // State update happens too late
    balances[msg.sender] = 0;
}
```

## Root Cause

The problem is the ordering.

The contract performs an external call while the user's balance is still recorded.

```text
CHECK
  ↓
INTERACTION
  ↓
EFFECT
```

The safer pattern is:

```text
CHECK
  ↓
EFFECT
  ↓
INTERACTION
```

---

# Reentrancy Attack

The vulnerable execution flow is:

```text
User calls withdraw()
        ↓
Bank reads user's balance
        ↓
Bank sends ETH to user
        ↓
Attacker's receive() executes
        ↓
Attacker calls withdraw() again
        ↓
Bank reads the same balance
        ↓
Bank sends ETH again
        ↓
Attacker callback executes again
        ↓
Repeat
```

The critical condition is:

```text
External call
      ↓
State has not been updated yet
      ↓
Attacker re-enters
```

The attacker can therefore re-enter the withdrawal function before the original invocation reaches:

```solidity
balances[msg.sender] = 0;
```

---

# Why `call{value: ...}("")` Creates the Callback

The vulnerable bank sends ETH using:

```solidity
msg.sender.call{value: amount}("");
```

If `msg.sender` is a contract, its `receive()` or fallback function can execute.

The attacker uses this callback to call the bank again.

Example:

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

This creates recursive execution.

The number of recursive calls in this lab is intentionally limited:

```solidity
callCount < 10
```

This makes the exploit deterministic and prevents uncontrolled recursion during testing.

---

# Attacker Contract

`Attacker.sol` performs three main tasks.

## 1. Store the target bank

```solidity
VulnerableBank public bank;
```

## 2. Deposit an initial amount

```solidity
bank.deposit{value: amount}();
```

## 3. Start the attack

```solidity
bank.withdraw();
```

When the bank sends ETH back to the attacker contract, the attacker's `receive()` function executes and attempts another withdrawal.

---

# Attack Flow

A simplified example:

```text
Attacker
   |
   | deposit 1 ETH
   v
VulnerableBank
   |
   | withdraw()
   v
Bank sends 1 ETH
   |
   v
Attacker.receive()
   |
   | withdraw()
   v
Bank sends 1 ETH again
   |
   v
Attacker.receive()
   |
   | withdraw()
   v
Repeat
```

---

# Proof of Concept

The Foundry test:

```solidity
function test_ReentrancyDrainsBank() public
```

creates the following environment:

```text
Bank balance   = 10 ETH
Attacker deposit = 1 ETH
```

The attacker then starts the withdrawal.

The test verifies that:

- Multiple reentrant calls occur
- More than one withdrawal occurs
- The attacker receives more ETH than initially deposited
- The bank loses ETH
- The exploit succeeds against the vulnerable implementation

The exact result depends on the contract balance and attack parameters.

---

# Important Security Observation

The vulnerability is **not caused by `call()` itself**.

The problem is the combination of:

```text
External call
+
State update after the call
```

Using a low-level ETH transfer is not inherently a reentrancy vulnerability.

The dangerous pattern is:

```text
CHECK
  ↓
INTERACTION
  ↓
EFFECT
```

instead of:

```text
CHECK
  ↓
EFFECT
  ↓
INTERACTION
```

---

# Defense — Checks-Effects-Interactions

The first remediation is the **Checks-Effects-Interactions (CEI)** pattern.

The correct order is:

```text
1. CHECKS
      ↓
2. EFFECTS
      ↓
3. INTERACTIONS
```

## 1. Checks

Validate the withdrawal conditions.

```solidity
uint256 amount = balances[msg.sender];

require(
    amount > 0,
    "No balance"
);
```

## 2. Effects

Update the accounting state before the external call.

```solidity
balances[msg.sender] = 0;
totalDeposits -= amount;
```

## 3. Interactions

Only after state has been updated does the contract send ETH.

```solidity
(bool success, ) =
    msg.sender.call{value: amount}("");

require(
    success,
    "Transfer failed"
);
```

---

# Secure Withdrawal

`SecureBank.sol` implements the corrected ordering:

```solidity
function withdraw() external nonReentrant {
    // CHECKS
    uint256 amount = balances[msg.sender];

    require(
        amount > 0,
        "No balance"
    );

    // EFFECTS
    balances[msg.sender] = 0;
    totalDeposits -= amount;

    // INTERACTIONS
    (bool success, ) =
        msg.sender.call{value: amount}("");

    require(
        success,
        "Transfer failed"
    );

    emit Withdrawn(
        msg.sender,
        amount
    );
}
```

If the attacker attempts to re-enter:

```text
balances[msg.sender] == 0
```

so the repeated withdrawal cannot withdraw the same recorded balance.

---

# Reentrancy Guard

`SecureBank` also contains a custom `nonReentrant` modifier.

```solidity
uint256 private constant _NOT_ENTERED = 1;
uint256 private constant _ENTERED = 2;

uint256 private _status = _NOT_ENTERED;
```

The modifier:

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

The first call changes the state to:

```text
_ENTERED
```

A recursive call then encounters:

```text
_status == _ENTERED
```

and is rejected.

---

# Defense in Depth

The secure implementation demonstrates two complementary protections:

| Protection | Purpose | Key consideration |
|---|---|---|
| CEI | Updates state before external interaction | Requires correct state ordering |
| `nonReentrant` | Prevents nested execution | Should complement, not replace, correct accounting |

The important lesson is that a reentrancy guard should not be treated as a substitute for correct state management.

For production systems, a well-tested library implementation such as OpenZeppelin's `ReentrancyGuard` should generally be preferred over maintaining a custom implementation without additional review.

---

# Testing Strategy

The project uses **Foundry / Forge**.

Testing is divided into:

```text
Vulnerability Tests
        ↓
Fuzz Tests
        ↓
Secure Implementation Tests
        ↓
Regression Tests
```

---

# Vulnerability Tests

`ReentrancyTest.t.sol` verifies the vulnerable behavior.

## Successful Reentrancy

The test:

```solidity
test_ReentrancyDrainsBank()
```

checks that:

- The attacker can execute multiple callbacks
- More than one withdrawal occurs
- The attacker receives more than the original deposit
- The bank balance decreases

## Normal Withdrawal

The test:

```solidity
test_NormalUserCannotWithdrawMoreThanDeposit()
```

verifies that a normal user can:

```text
deposit
   ↓
withdraw
   ↓
balance becomes zero
```

without using the reentrancy attack.

---

# Fuzz Testing

The project includes the Foundry fuzz test:

```solidity
testFuzz_ReentrancyAlwaysSteals(
    uint256 depositAmount
)
```

The input is bounded to a controlled range:

```solidity
depositAmount = bound(
    depositAmount,
    0.1 ether,
    1 ether
);
```

This tests the attack with multiple generated deposit values.

The test verifies that the attacker at least receives back the original deposit amount.

> The current fuzz test is primarily a robustness test around the attack setup. It should not be interpreted as formally proving that every generated input results in a profitable exploit.

---

# SecureBank Tests

`SecureBankAttacker.t.sol` verifies the defensive implementation.

## Normal Withdrawal Works

The test confirms that legitimate users can still withdraw their funds.

It verifies:

```text
Deposit
   ↓
Balance recorded
   ↓
Withdraw
   ↓
User receives ETH
   ↓
Recorded balance becomes zero
```

## Reentrancy Attack Is Blocked

The test deploys a malicious attacker contract against `SecureBank`.

The attacker attempts to:

```text
deposit
   ↓
withdraw
   ↓
receive()
   ↓
withdraw() again
```

The reentrant attempt is blocked by the secure implementation.

The attacker retains only the amount corresponding to the legitimate deposit.

## Balance Is Cleared

The tests also verify:

```solidity
bank.balances(user) == 0
```

after a successful withdrawal.

This is an important accounting invariant for the withdrawal flow.

---

# Test Results

The latest recorded Foundry test run produced:

```text
Ran 2 test suites:

6 tests passed
0 failed
0 skipped
```

## SecureBank Test Suite

```text
Ran 3 tests for test/SecureBankAttacker.t.sol:SecureBankTest

[PASS] test_BalanceIsZeroAfterWithdraw()
[PASS] test_NormalWithdrawWorks()
[PASS] test_ReentrancyGuardBlocksAttack()

Suite result:
3 passed
0 failed
0 skipped
```

## VulnerableBank Test Suite

```text
Ran 3 tests for test/ReentrancyTest.t.sol:ReentrancyTest

[PASS] testFuzz_ReentrancyAlwaysSteals(uint256)
[PASS] test_NormalUserCannotWithdrawMoreThanDeposit()
[PASS] test_ReentrancyDrainsBank()

Suite result:
3 passed
0 failed
0 skipped
```

## Overall

| Metric | Result |
|---|---:|
| Test suites | **2** |
| Total tests | **6** |
| Passed | **6** |
| Failed | **0** |
| Skipped | **0** |
| Fuzz runs | **256** |

All recorded tests passed successfully.

---

# Coverage

The latest `forge coverage` result:

```text
File                          % Lines        % Statements   % Branches     % Funcs

src/Attacker.sol              87.50% (14/16) 91.67% (11/12) 66.67% (2/3)   75.00% (3/4)

src/SecureBank.sol            90.00% (18/20) 93.75% (15/16) 62.50% (5/8)   75.00% (3/4)

src/VulnerableBank.sol        85.71% (12/14) 90.91% (10/11) 50.00% (3/6)   66.67% (2/3)

test/SecureBankAttacker.t.sol 100.00% (12/12) 100.00% (9/9)  100.00% (2/2)  100.00% (3/3)

Total                         90.32% (56/62) 93.75% (45/48) 63.16% (12/19) 78.57% (11/14)
```

## Coverage Summary

| Metric | Coverage |
|---|---:|
| Lines | **90.32% (56/62)** |
| Statements | **93.75% (45/48)** |
| Branches | **63.16% (12/19)** |
| Functions | **78.57% (11/14)** |

## Contract Coverage

| Contract | Lines | Statements | Branches | Functions |
|---|---:|---:|---:|---:|
| `Attacker.sol` | 87.50% | 91.67% | 66.67% | 75.00% |
| `SecureBank.sol` | 90.00% | 93.75% | 62.50% | 75.00% |
| `VulnerableBank.sol` | 85.71% | 90.91% | 50.00% | 66.67% |

The test contract `SecureBankAttacker.t.sol` has 100% coverage across lines, statements, branches, and functions.

Coverage is used as an engineering signal and does not by itself establish security or correctness.

---

# Run the Project

## Prerequisites

Install:

- Foundry
- Git

---

# Clone the Repository

```bash
git clone https://github.com/Pravinru17/reentrancy-lab.git
```

Enter the repository:

```bash
cd reentrancy-lab
```

---

# Build

Compile the contracts:

```bash
forge build
```

---

# Format

Format the Solidity code:

```bash
forge fmt
```

Check formatting:

```bash
forge fmt --check
```

---

# Run Tests

Run the complete test suite:

```bash
forge test
```

Run with detailed output:

```bash
forge test -vv
```

Run with maximum trace verbosity:

```bash
forge test -vvvv
```

---

# Run Coverage

```bash
forge coverage
```

---

# Run Specific Tests

Run the vulnerable-bank tests:

```bash
forge test --match-contract ReentrancyTest
```

Run the secure-bank tests:

```bash
forge test --match-contract SecureBankTest
```

Run the exploit test:

```bash
forge test --match-test test_ReentrancyDrainsBank
```

---

# Security Analysis

The project can also be analyzed with static-analysis tools such as:

```bash
slither .
```

The intentionally vulnerable contract is expected to contain security findings.

The secure implementation can then be compared against the vulnerable version.

---

# Audit Report

The repository contains:

```text
AUDIT.md
```

The audit documentation covers:

- Vulnerability description
- Root cause
- Vulnerable code
- Attack flow
- Proof of concept
- Impact
- Remediation
- CEI implementation
- Reentrancy guard
- Security recommendations
- Testing results

---

# Vulnerability Summary

## Vulnerability

**Single-function reentrancy**

## Root Cause

The vulnerable contract performs an external ETH transfer before updating the user's balance.

```text
External interaction
        ↓
State update
```

This allows the recipient contract to execute code while the original state is still unchanged.

## Impact

In this controlled educational lab, the vulnerable bank can lose ETH through repeated withdrawals against the attacker's unchanged recorded balance.

The practical impact of the same vulnerability in a real application would depend on:

- Contract balance
- Attacker-controlled state
- Withdrawal logic
- Other accounting mechanisms
- Available liquidity
- Additional access controls

---

# Remediation

The project demonstrates two remediation techniques.

## 1. Checks-Effects-Interactions

Update internal accounting before making the external call.

## 2. Reentrancy Guard

Prevent the protected function from being entered recursively during the same execution.

For production systems, a well-tested library implementation such as OpenZeppelin's `ReentrancyGuard` should generally be preferred over maintaining a custom implementation without additional review.

---

# Security Lessons

This project demonstrates several important smart-contract security principles.

## 1. External Calls Are Trust Boundaries

A contract should treat calls to unknown contracts as potentially executing arbitrary code.

## 2. State Should Be Updated Before External Interaction

This is the central principle behind CEI.

## 3. Reentrancy Is About Execution Flow

The attacker does not need to directly modify the bank's storage.

Instead, the attacker takes advantage of the fact that the bank temporarily exposes an inconsistent state during execution.

## 4. Tests Should Reproduce Real Attack Paths

A security test should demonstrate:

```text
Vulnerability
     ↓
Exploit
     ↓
Impact
     ↓
Fix
     ↓
Regression Test
```

---

# Learning Objectives

By completing this project, I practiced:

- Solidity external calls
- ETH transfers
- `receive()` functions
- EVM execution flow
- Reentrant execution
- State accounting
- Checks-Effects-Interactions
- Reentrancy guards
- Foundry testing
- Fuzz testing
- Attack simulation
- Security regression testing
- Vulnerability documentation

---

# What This Project Demonstrates

The project demonstrates a practical security workflow rather than only theoretical knowledge:

```text
Solidity
   ↓
Understand Vulnerability
   ↓
Reproduce Exploit
   ↓
Build PoC
   ↓
Understand Root Cause
   ↓
Implement CEI
   ↓
Add Reentrancy Protection
   ↓
Write Regression Tests
   ↓
Run Fuzz Tests
   ↓
Document Findings
```

---

# Educational Disclaimer

`VulnerableBank.sol` and `Attacker.sol` are intentionally designed for security education.

They should **never be deployed with real funds**.

`SecureBank.sol` demonstrates defensive techniques but should not be considered production-ready solely because these tests pass.

Production smart contracts require additional:

- Testing
- Static analysis
- Integration testing
- Security review
- Economic analysis where applicable
- Formal verification where appropriate

---

# Author

**Pravin R**

Junior Solidity / Blockchain Developer

### GitHub

https://github.com/Pravinru17

---

# License

MIT
