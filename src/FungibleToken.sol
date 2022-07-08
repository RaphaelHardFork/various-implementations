//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";

interface Oracle {
    function lastestAnswer() external view returns (int256);
}

contract FungibleToken is ERC20, Ownable {
    using Address for address payable;

    uint256 internal constant PRECISION = 10**25;
    Oracle private _oracle;

    constructor() ERC20("FungibleToken", "FT") {}

    function mint(uint256 amount) public {
        require(amount <= 50 * 10**18, "Mint no more than 50 tokens");
        require(balanceOf(msg.sender) <= 5 * 10**18, "You have enough tokens");
        _mint(msg.sender, amount);
    }

    function mintMore(uint256 amount) external payable returns (bool) {
        if (amount <= 50 * 10**18) {
            mint(amount);
            return true;
        }
        require(amount <= 1000 * 10**18, "Mint no more than 1000 tokens");
        require(ethToUsd(msg.value) >= 10**18, "You must donate at least 1$");
        _mint(msg.sender, amount);
        return true;
    }

    function setOracle(Oracle oracle) external onlyOwner {
        require(oracle.lastestAnswer() > 0, "Oracle is not working");
        _oracle = oracle;
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).sendValue(address(this).balance);
    }

    function ethToUsd(uint256 amount) public view returns (uint256) {
        // amount in wei
        return
            amount *
            ((
                ((((uint256(_oracle.lastestAnswer()) * PRECISION) / 10**8) *
                    10**18) / PRECISION)
            ) / 10**18);
    }

    function usdToEth(uint256 amount) public view returns (uint256) {
        // amount in wei
        return
            amount /
            (((((uint256(_oracle.lastestAnswer()) * PRECISION) / 10**8) *
                10**18) / PRECISION) / 10**18);
    }
}
