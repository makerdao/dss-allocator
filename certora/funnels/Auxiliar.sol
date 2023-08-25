// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract Auxiliar {
    function decode(bytes calldata data) external pure returns (address gem0, address gem1, uint24 fee) {
        (gem0, gem1, fee) = abi.decode(data, (address, address, uint24));
    }
}
