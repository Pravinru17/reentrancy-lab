// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/SecureBank.sol";

contract SecureBankAttacker {
    SecureBank public bank;
    uint256 public callCount;

    constructor(address _bank) {
        bank = SecureBank(_bank);
    }

    receive() external payable {
        callCount++;

        if (
            address(bank).balance >= 1 ether &&
            callCount < 5
        ) {
            try bank.withdraw() {
            } catch {
            }
        }
    }

    function attack() external payable {
        callCount = 0;

        bank.deposit{value: msg.value}();
        bank.withdraw();
    }
}

contract SecureBankTest is Test {
    SecureBank public bank;
    address public user;

    function setUp() public {
        bank = new SecureBank();
        user = makeAddr("user");
    }

    function test_NormalWithdrawWorks() public {
        vm.deal(user, 2 ether);

        vm.prank(user);
        bank.deposit{value: 2 ether}();

        assertEq(
            bank.balances(user),
            2 ether
        );

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        bank.withdraw();

        uint256 balanceAfter = user.balance;

        assertEq(
            balanceAfter - balanceBefore,
            2 ether
        );

        assertEq(
            bank.balances(user),
            0
        );
    }

    function test_ReentrancyGuardBlocksAttack() public {
        SecureBankAttacker attacker =
            new SecureBankAttacker(address(bank));

        vm.deal(address(bank), 10 ether);

        attacker.attack{value: 1 ether}();

        assertEq(
            address(attacker).balance,
            1 ether
        );

        assertGt(
            attacker.callCount(),
            0
        );

        console.log(
            "Attacker balance:",
            address(attacker).balance
        );

        console.log(
            "Reentrancy attempts:",
            attacker.callCount()
        );
    }

    function test_BalanceIsZeroAfterWithdraw() public {
        vm.deal(user, 1 ether);

        vm.prank(user);
        bank.deposit{value: 1 ether}();

        assertEq(
            bank.balances(user),
            1 ether
        );

        vm.prank(user);
        bank.withdraw();

        assertEq(
            bank.balances(user),
            0
        );
    }
}