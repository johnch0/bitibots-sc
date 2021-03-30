// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "../BitiToken.sol";

contract BitiTest is Biti {
  address private _minter;
  constructor() Biti() {
    _minter = msg.sender;
  }

  function mintTo(address _to, uint256 _amount) external onlyMinter {
    _mint(_to, _amount);
  }

  modifier onlyMinter() {
      require(_minter == msg.sender, "caller is not the _minter");
      _;
  }
}
