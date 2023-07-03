// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// based on https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
library PoolAddress {
    function getPoolAddress(address factory, address gem0, address gem1, uint24 fee) internal pure returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encode(gem0, gem1, fee)),
                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
            )))));
    }
}