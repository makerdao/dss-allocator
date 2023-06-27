// SPDX-FileCopyrightText: © 2020 Lev Livnev <lev@liv.nev.org.uk>
// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

interface SwapperLike {
    function swap(address src, address dst, uint256 amt, uint256 minOut, address callee, bytes calldata data) external returns (uint256 out);
}

contract StableSwapper {
    mapping (address => uint256) public wards;                          // facilitators
    mapping (address => uint256) public buds;                           // whitelisted keepers
    mapping (address => mapping (address => uint256)) public counts;    // counts[src][dst] is the remaining number of times that a src-to-dst swap can be performed by keepers
    mapping (address => mapping (address => uint256)) public lots;      // [token weis] lots[src][dst] is the amount swapped by keepers from src to dst every hop
    mapping (address => mapping (address => uint256)) public minPrices; // [WAD] minPrices[src][dst] is the minimum price to insist on in the swap form src to dst.
                                                                        //       This needs to take into account any difference in decimals between src and dst.
                                                                        //       Example 1: a max loss of 1% when swapping  USDC to DAI corresponds to minPrices[src][dst] = 99 * WAD / 100 * 10**(18-6)
                                                                        //       Example 2: a max loss of 1% when swapping  DAI to USDC corresponds to minPrices[src][dst] = 99 * WAD / 100 / 10**(18-6)
                                                                        //       Example 3: a max loss of 1% when swapping USDT to USDC corresponds to minPrices[src][dst] = 99 * WAD / 100

    address public swapper;                                             // Swapper for this StableSwapper

    event Rely   (address indexed usr);
    event Deny   (address indexed usr);
    event Kissed (address indexed usr);
    event Dissed (address indexed usr);
    event File   (bytes32 indexed what, address data);
    event File   (bytes32 indexed what, address indexed src, address indexed dst, uint256 data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableSwapper/not-authorized");
        _;
    }

    // permissionned to whitelisted keepers
    modifier toll { 
        require(buds[msg.sender] == 1, "StableSwapper/non-keeper"); 
        _;
    }

    uint256 internal constant WAD = 10 ** 18;

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    function kiss(address usr) external auth {  buds[usr] = 1; emit Kissed(usr); }
    function diss(address usr) external auth {  buds[usr] = 0; emit Dissed(usr); }

    function file(bytes32 what, address src, address dst, uint256 data) external auth {
        if      (what == "count")        counts[src][dst] = data;
        else if (what == "lot")            lots[src][dst] = data;
        else if (what == "minPrice")  minPrices[src][dst] = data;
        else revert("StableSwapper/file-unrecognized-param");
        emit File(what, src, dst, data);
    }

    function file(bytes32 what, address data) external auth {
        if   (what == "swapper") swapper = data;
        else revert("StableSwapper/file-unrecognized-param");
        emit File(what, data);
    }

    function swap(address src, address dst, uint256 minOut, address callee, bytes calldata data) toll external returns (uint256 out) {
        uint256 cnt = counts[src][dst];
        require(cnt > 0, "StableSwapper/exceeds-count");
        counts[src][dst] = cnt - 1;

        uint256 lot = lots[src][dst];
        uint256 reqOut = lot * minPrices[src][dst] / WAD;
        if(minOut == 0) minOut = reqOut;
        require(minOut >= reqOut, "SwapperRunner/min-too-small");

        out = SwapperLike(swapper).swap(src, dst, lot, minOut, callee, data);
    }
}
