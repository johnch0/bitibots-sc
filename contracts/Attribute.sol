// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./library/utils/SafeMath.sol";

contract Attribute {
    using SafeMath for uint;

    // 0 - eye
    // 1 - body
    // 2 - head
    // 3 - mouth
    // 4 - mental
    uint constant n = 5; // number of attributes

    uint randomNonce = 0;

    function getAttribute(uint attrs, uint index) public pure returns (uint) {
        return (attrs.div(10**index)) % 10;
    }

    function randomEyeAttribute() virtual public returns (uint) {
        uint r = random(100);
        if (r < 20) { // 20%
            return 0;
        } else if (r < 40) { // 20%
            return 1;
        } else if (r < 60) { // 20%
            return 2;
        } else if (r < 75) { // 15%
            return 3;
        } else if (r < 90) { // 15%
            return 4;
        } else { // 10%
            return 5;
        }
    }

    function randomAllAttributes() public returns (uint) {
        uint offspring = 0;
        for (uint i = n-1; i >= 1; i--) {
            offspring = offspring.add(random(10));
            offspring *= 10;
        }
        offspring = offspring.add(randomEyeAttribute());
        return offspring;
    }

    function mixAttributes(uint sire, uint matron) public returns (uint) {
        uint sireEye = getAttribute(sire, 0);
        uint matronEye = getAttribute(matron, 0);
        require(sireEye == matronEye, "parents must have the same eye attribute");

        uint offspring = 0;
        for (uint i = n-1; i >= 1; i--) {
            uint r = random(100);
            if (r < 40) {
                offspring = offspring.add(getAttribute(sire, i));
            } else if (r < 80) {
                offspring = offspring.add(getAttribute(matron, i));
            } else {
                // offspring += ((getAttribute(sire, i) + 1) * (getAttribute(matron, i) + 1) * r) % 10;
                offspring = offspring.add(random(10));
            }
            offspring = offspring.mul(10);
        }

        offspring = offspring.add(sireEye);
        return offspring;
    }

    function random(uint max) private returns (uint) {
        randomNonce = randomNonce.add(1);
        return uint(keccak256(abi.encodePacked(block.timestamp, randomNonce))) % max;
    }

    // @dev temp func
    function clamp(uint value, uint min, uint max) public pure returns (uint) {
        return (value < min) ? min : (value > max) ? max : value;
    }

}
