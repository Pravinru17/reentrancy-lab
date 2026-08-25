// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/VulnerableBank.sol";
import "../src/Attacker.sol";

contract ReentrancyTest is Test {
    VulnerableBank public bank;
    Attacker public attacker;

    address public attackerEOA;
    address public user;

    function setUp() public {
        bank = new VulnerableBank();
        attacker = new Attacker(address(bank));

        attackerEOA = makeAddr("attackerEOA");
        user = makeAddr("user");

        // Bank starts with 10 ETH
        vm.deal(address(bank), 10 ether);
    }

    function test_ReentrancyDrainsBank() public {
        vm.deal(attackerEOA, 1 ether);

        uint256 bankBalanceBefore = address(bank).balance;

        console.log("=== BEFORE ATTACK ===");
        console.log("Bank balance:", bankBalanceBefore);
        console.log("Attacker balance:", address(attacker).balance);

        vm.prank(attackerEOA);
        attacker.attack{value: 1 ether}(1 ether);

        uint256 bankBalanceAfter = address(bank).balance;
        uint256 attackerBalanceAfter = address(attacker).balance;
        uint256 callCount = attacker.callCount();

        console.log("=== AFTER ATTACK ===");
        console.log("Bank balance:", bankBalanceAfter);
        console.log("Attacker balance:", attackerBalanceAfter);
        console.log("Reentrancy calls made:", callCount);

        assertGt(
            attackerBalanceAfter,
            1 ether,
            "Attacker should have more than deposited"
        );

        assertLt(
            bankBalanceAfter,
            bankBalanceBefore,
            "Bank should have less ETH"
        );

        assertGt(
            callCount,
            1,
            "Should have made multiple reentrancy calls"
        );

        console.log("=== EXPLOIT SUCCESSFUL ===");
        console.log(
            "Stolen:",
            attackerBalanceAfter - 1 ether
        );
    }

    function test_NormalUserCannotWithdrawMoreThanDeposit() public {
        vm.deal(user, 2 ether);

        vm.prank(user);
        bank.deposit{value: 2 ether}();

        assertEq(
            bank.balances(user),
            2 ether
        );

        vm.prank(user);
        bank.withdraw();

        assertEq(
            bank.balances(user),
            0
        );
    }

    function testFuzz_ReentrancyAlwaysSteals(
        uint256 depositAmount
    ) public {
        depositAmount = bound(
            depositAmount,
            0.1 ether,
            1 ether
        );

        vm.deal(address(bank), 20 ether);
        vm.deal(attackerEOA, depositAmount);

        vm.prank(attackerEOA);
        attacker.attack{value: depositAmount}(
            depositAmount
        );

        assertGe(
            address(attacker).balance,
            depositAmount,
            "Attacker should at least get deposit back"
        );
    }
}