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

interface BufferLike {
    function take(address to, uint256 wad) external;
}

interface GemLike {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRlefter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);

    // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/interfaces/ISwapRouter.sol#L26
    // https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

contract Swapper {
    mapping (address => uint256) public wards;
    mapping (address => uint256) public buds;     // whitelisted facilitators
    mapping (address => uint256) public keepers;  // whitelisted keepers

    address public buffer;         // Allocation buffer for this Swapper
    address public escrow;         // Contract from which the GEM to sell is pulled before a GEM-to-NST swap or to which the bought GEM is pushed after a NST-to-GEM swap
    uint256 public hop;            // [seconds]   Swap cooldown (set by governance)
    uint256 public nstToGemCount;  // [count]     Remaining number of times that a nst-to-gem swap can be performed (set by facilitators)
    uint256 public gemToNstCount;  // [count]     Remaining number of times that a gem-to-nst swap can be performed (set by facilitators)
    uint256 public nstLot;         // [WAD]       Amount swapped from nst to gem every hop (set by facilitators)
    uint256 public gemLot;         // [WAD]       Amount swapped from gem to nst every hop (set by facilitators)
    uint256 public maxNstLot;      // [WAD]       Max allowable nstLot (set by governance)
    uint256 public maxGemLot;      // [WAD]       Max allowable gemLot (set by governance)
    uint256 public minNstPrice;    // [WAD]       Relative multiplier of the reference price (equal to 1 gem/nst) to insist on in the swap from nst to gem (set by governance)
    uint256 public minGemPrice;    // [WAD]       Relative multiplier of the reference price (equal to 1 nst/gem) to insist on in the swap from gem to nst (set by governance)
    uint256 public zzz;            // [Timestamp] Last swap

    event Rely   (address indexed usr);
    event Deny   (address indexed usr);
    event Kissed (address indexed usr);
    event Dissed (address indexed usr);
    event Permit (address indexed usr);
    event Forbid (address indexed usr);
    event File   (bytes32 indexed what, uint256 data);
    event File   (bytes32 indexed what, address data);
    event File   (bytes32 indexed what, address data, uint256 val);
    event Lots   (address indexed bud, uint256 nstLot, uint256 gemLot);
    event Counts (address indexed bud, uint256 nstToGemCount, uint256 gemToNstCount);
    event Swap   (address indexed kpr, address indexed from, address indexed to, uint256 amt, uint256 out);
    event Quit   (address indexed usr, uint256 wad);


    constructor(address _nst, address _gem, address _uniV3Router, uint256 _fee) {
        nst = _nst;
        gem = _gem;
        decimals = GemLike(gem).decimals();
        uniV3Router = _uniV3Router;
        fee = _fee;

        GemLike(nst).approve(uniV3Router, type(uint256).max);
        GemLike(gem).approve(uniV3Router, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "Swapper/not-authorized");
        _;
    }

    // permissionned to whitelisted facilitators
    modifier toll { 
        require(buds[msg.sender] == 1, "Swapper/non-facilitator"); 
        _;
    }

    // permissionned to whitelisted keepers
    modifier keeper { 
        require(keepers[msg.sender] == 1, "Swapper/non-keeper"); 
        _;
    }

    uint256 internal constant WAD = 10 ** 18;

    uint8   public immutable decimals;     // gem.decimals()
    uint256 public immutable fee;          // [BPS] UniV3 pool fee
    address public immutable uniV3Router;
    address public immutable nst;
    address public immutable gem;

    function rely(address usr)   external auth { wards[usr]   = 1; emit Rely(usr); }
    function deny(address usr)   external auth { wards[usr]   = 0; emit Deny(usr); }
    function kiss(address usr)   external auth { buds[usr]    = 1; emit Kissed(usr); }
    function diss(address usr)   external auth { buds[usr]    = 0; emit Dissed(usr); }
    function permit(address usr) external toll { keepers[usr] = 1; emit Permit(usr); }
    function forbid(address usr) external toll { keepers[usr] = 0; emit Forbid(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "maxNstLot")   maxNstLot   = data;
        else if (what == "maxGemLot")   maxGemLot   = data;
        else if (what == "minNstPrice") minNstPrice = data;
        else if (what == "minGemPrice") minGemPrice = data;
        else if (what == "hop")         hop         = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if      (what == "escrow") escrow = data;
        else if (what == "buffer") buffer = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function setLots(uint256 _nstLot, uint256 _gemLot)  external toll {
        require(_nstLot <= maxNstLot, "Swapper/exceeds-max-nst-lot");
        require(_gemLot <= maxGemLot, "Swapper/exceeds-max-gem-lot");
        nstLot = _nstLot;
        gemLot = _gemLot;
        emit Lots(msg.sender, _nstLot, _gemLot);
    }

    function setCounts(uint256 _nstToGemCount, uint256 _gemToNstCount)  external toll {
        nstToGemCount = _nstToGemCount;
        gemToNstCount = _gemToNstCount;
        emit Counts(msg.sender, _nstToGemCount, _gemToNstCount);
    }

    function nstToGem(uint256 min) external keeper returns (uint256 out) {
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        uint256 amt = nstLot;
        require(min >= amt * minNstPrice / 10**(36 - decimals), "Swapper/min-too-small"); // 1/10^(36-d) = 1/WAD * 1/WAD * 10^d

        uint256 cnt = nstToGemCount;
        require(cnt > 0, "Swapper/exceeds-count");
        nstToGemCount = cnt - 1;

        BufferLike(buffer).take(address(this), amt);

        bytes memory path = abi.encodePacked(nst, uint24(fee), gem);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         amt,
            amountOutMinimum: min
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        GemLike(gem).transfer(escrow, out);

        emit Swap(msg.sender, nst, gem, amt, out);
    }

    function gemToNst(uint256 min) external keeper returns (uint256 out) {
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        uint256 amt = gemLot;
        require(min >= amt * minGemPrice / 10**decimals, "Swapper/min-too-small"); // 1/10^d = 1/10^d * 1/WAD * WAD
        
        uint256 cnt = gemToNstCount;
        require(cnt > 0, "Swapper/exceeds-count");
        gemToNstCount = cnt - 1;

        GemLike(gem).transferFrom(escrow, address(this), amt);

        bytes memory path = abi.encodePacked(gem, uint24(fee), nst);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         amt,
            amountOutMinimum: min
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        GemLike(nst).transfer(buffer, out);

        emit Swap(msg.sender, gem, nst, amt, out);
    }
}
