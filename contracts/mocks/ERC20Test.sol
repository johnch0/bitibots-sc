// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.4.23;

import "../library/ERC20.sol";

contract ERC20Test is ERC20 {

  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function setBalance(address holder, uint256 amount) public {
    _mint(holder, amount);
  }
}
