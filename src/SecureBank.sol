// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SecureBank {
    mapping(address => uint256) public balances;

    uint256 public totalDeposits;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status = _NOT_ENTERED;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    modifier nonReentrant() {
        require(
            _status != _ENTERED,
            "ReentrancyGuard: reentrant call"
        );

        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }

    function deposit() external payable {
        require(
            msg.value > 0,
            "Must deposit something"
        );

        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(
            msg.sender,
            msg.value
        );
    }

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

    function getBalance()
        external
        view
        returns (uint256)
    {
        return address(this).balance;
    }
}