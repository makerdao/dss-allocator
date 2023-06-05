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
    function wipe(uint256 wad) external;
}

interface BoxLike { // aka "Conduit"
    function deposit(address gem, uint256 wad) external;
}

interface GemLike {
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface VatLike {
    function live() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRlefter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
    function factory() external returns (address factory);

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
    mapping (address => uint256) public boxes;    // whitelisted conduits
    
    address public buffer;         // Allocation buffer for this Swapper
    uint256 public hop;            // [seconds]   Swap cooldown (set by governance)
    uint256 public nstToGemCount;  // [WAD]       Remaining number of time that a nst-to-gem swap can be performed (set by facilitators)
    uint256 public gemToNstCount;  // [WAD]       Remaining number of time that a gem-to-nst swap can be performed (set by facilitators)
    uint256 public nstLot;         // [WAD]       Amount swapped from nst to gem every hop (set by facilitators)
    uint256 public gemLot;         // [WAD]       Amount swapped from gem to nst every hop (set by facilitators)
    uint256 public maxNstLot;      // [WAD]       Max allowable nstLot (set by governance)
    uint256 public maxGemLot;      // [WAD]       Max allowable gemLot (set by governance)
    uint256 public gemWant;        // [WAD]       Relative multiplier of the reference price (equal to 1 gem/nst) to insist on in the swap from nst to gem (set by governance)
    uint256 public nstWant;        // [WAD]       Relative multiplier of the reference price (equal to 1 nst/gem) to insist on in the swap from gem to nst (set by governance)
    uint256 public zzz;            // [Timestamp] Last swap

    uint256[] internal weights;   // Bit vector tightly packing (address(box), uint96(percentage)) tuple entries such that the sum of all percentages = 1 WAD (100%) (set by facilitators)

    struct Weight {
        address box;
        uint96 wad; // percentage in WAD such that 1 WAD = 100%
    }

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
    event Weights(address indexed bud, Weight[] weights);
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
        if      (what == "maxNstLot")  maxNstLot = data;
        else if (what == "maxGemLot")  maxGemLot = data;
        else if (what == "gemWant")    gemWant   = data;
        else if (what == "nstWant")    nstWant   = data;
        else if (what == "hop")        hop       = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "buffer") buffer = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data, uint256 val) external auth {
        if (what == "box") boxes[data] = val;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data, val);
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

    function setWeights(Weight[] memory newWeights) external toll {
        uint256 cumPct;
        uint256[] memory arr = new uint256[](newWeights.length);
        for(uint256 i; i < newWeights.length;) {
            (address _box, uint256 _pct) = (newWeights[i].box, uint256(newWeights[i].wad));
            arr[i] = (uint256(uint160(_box)) << 96) | _pct;
            cumPct += _pct;
            unchecked { ++i; }
        }
        require(cumPct == WAD, "Swapper/total-weight-not-wad");
        weights = arr;
        emit Weights(msg.sender, newWeights);
    }

    function getWeightAt(uint256 i) public view returns (address box, uint256 percent) {
        uint256 weight = weights[i];
        (box, percent) = (address(uint160(weight >> 96)), weight & (2**96 - 1));
        require(boxes[box] == 1, "Swapper/invalid-box"); // sanity check that any deauthorised box has also been removed from the weights vector
    }

    function getWeightsLength() external view returns (uint256 len) {
        len = weights.length;
    }

    function nstToGem(uint256 min) external keeper returns (uint256 out) {
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        uint256 amt = nstLot;
        require(min >= amt * gemWant / 10**(36 - decimals), "Swapper/min-too-small"); // 1/10^(36-d) = 1/WAD * 1/WAD * 10^d

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

        uint256 pending = out;
        uint256 len = weights.length;
        for(uint256 i; i < len;) {
            (address _to, uint256 _percent) = getWeightAt(i);
            uint256 _amt = (i == len - 1) ? pending : out * _percent / WAD;

            require(GemLike(gem).transfer(_to, _amt));
            BoxLike(_to).deposit(gem, _amt);

            pending -= _amt;
            unchecked { ++i; }
        }

        emit Swap(msg.sender, nst, gem, amt, out);
    }

    function gemToNst(uint256 min) external keeper returns (uint256 out) {
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        uint256 amt = gemLot;
        require(min >= amt * nstWant / 10**decimals, "Swapper/min-too-small"); // 1/10^d = 1/10^d * 1/WAD * WAD
        
        uint256 cnt = gemToNstCount;
        require(cnt > 0, "Swapper/exceeds-count");
        gemToNstCount = cnt - 1;

        uint256 pending = amt;
        uint256 len = weights.length;
        for(uint256 i; i < len;) {
            (address _from, uint256 _percent) = getWeightAt(i);
            uint256 _amt = (i == len - 1) ? pending : amt * _percent / WAD;

            // We assume the swapper was set as operator when calling box.initiateWithdrawal() and has
            // subsequently been granted a gem allowance by the box in box.completeWithdrawal()
            require(GemLike(gem).transferFrom(_from, address(this), _amt));

            pending -= _amt;
            unchecked { ++i; }
        }

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
        BufferLike(buffer).wipe(out);

        emit Swap(msg.sender, gem, nst, amt, out);
    }
}
