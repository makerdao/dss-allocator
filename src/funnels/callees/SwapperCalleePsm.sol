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

interface GemLike {
    function approve(address, uint256) external;
    function decimals() external view returns (uint8);
}

interface PsmLike {
    function sellGemNoFee(address usr, uint256 gemAmt) external returns (uint256 daiOutWad);
    function buyGemNoFee(address usr, uint256 gemAmt) external returns (uint256 daiInWad);
    function dai() external returns (address);
    function gem() external returns (address);
}

contract SwapperCalleePsm {
    mapping (address => uint256) public wards;

    address public immutable psm;
    address public immutable gem;
    uint256 public immutable to18ConversionFactor;

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address _psm) {
        psm = _psm;
        gem = PsmLike(psm).gem();
        GemLike(PsmLike(psm).dai()).approve(address(psm), type(uint256).max);
        GemLike(gem).approve(address(psm), type(uint256).max);
        to18ConversionFactor = 10 ** (18 - GemLike(gem).decimals());

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "SwapperCalleePsm/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function swapCallback(address src, address /* dst */, uint256 amt, uint256 /* minOut */, address to, bytes calldata /* data */) external auth {
        if (src == gem) PsmLike(psm).sellGemNoFee(to, amt);
        else            PsmLike(psm).buyGemNoFee (to, amt / to18ConversionFactor);
    }
}
