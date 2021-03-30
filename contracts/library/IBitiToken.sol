// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
/**
 * @dev Extend IERC20 Interface to add minting functions
 */
interface IBitiToken is IERC20 {
    function mint(address to, uint256 amount) external;
}
