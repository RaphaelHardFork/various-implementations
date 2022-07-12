//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";

contract BasicERC20 is ERC20, Ownable {
    using Address for address payable;

    constructor() ERC20("BasicERC20", "TOKEN") {}

    function mint(address receiver, uint256 amount) public onlyOwner {
        _mint(receiver, amount);
    }
}
