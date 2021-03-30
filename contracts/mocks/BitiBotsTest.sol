// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.6;

import "../BitiBots.sol";
import "../library/IBitiToken.sol";

contract BitiBotsTest is BitiBots {
  constructor(IBitiToken _biti, uint _startBlock, address _feeCollector) BitiBots(_biti, _startBlock, _feeCollector) {}

  function randomEyeAttribute() override public returns (uint) {
      return 1;
  }
}
