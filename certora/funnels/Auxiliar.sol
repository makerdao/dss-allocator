// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract Auxiliar {
    function getHash(address addr, int24 tickLower, int24 tickUpper) external pure returns (bytes32 hashC) {
        hashC = keccak256(abi.encodePacked(addr, tickLower, tickUpper));
    }

    function decode(bytes calldata data) external pure returns (address gem0, address gem1, uint24 fee) {
        (gem0, gem1, fee) = abi.decode(data, (address, address, uint24));
    }
}
