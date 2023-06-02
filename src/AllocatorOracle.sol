// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

contract AllocatorOracle {
    // 1M price together with 1M supply, allows up to 1T DAI minting
    // and it is a good balance for collateral redemption in Global Shutdown
    uint256 internal constant PRICE = 10**6 * 10**18; // 1M in WAD

    /**
        @notice Return value and status of the oracle
        @return val PRICE constant
        @return ok always true
    */
    function peek() public pure returns (bytes32 val, bool ok) {
        val = bytes32(PRICE);
        ok  = true;
    }

    /**
        @notice Return value
        @return val PRICE constant
    */
    function read() external pure returns (bytes32 val) {
        val = bytes32(PRICE);
    }
}
