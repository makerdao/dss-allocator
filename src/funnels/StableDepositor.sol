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

interface DepositorLike {
    struct DepositParams {
        address gem0;
        address gem1;
        uint256 amt0;
        uint256 amt1;
        uint256 minAmt0;
        uint256 minAmt1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function deposit(DepositParams memory params) external returns (
        uint128 liquidity,
        uint256 amt0,
        uint256 amt1
    );

    struct WithdrawParams {
        address gem0;
        address gem1;
        uint128 liquidity;
        uint256 minAmt0;
        uint256 minAmt1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function withdraw(WithdrawParams memory p) external returns (
        uint256 amt0,
        uint256 amt1
    );
}

interface UniV3PoolLike {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

// Mock for now
library LiquidityAmounts {
    function getLiquidityForAmount0(
        uint160,
        uint160,
        uint256
    ) internal pure returns (uint128) {
        return uint128(0);
    }

    function getLiquidityForAmount1(
        uint160,
        uint160,
        uint256
    ) internal pure returns (uint128) {
        return uint128(0);
    }
}

// Mock for now
library TickMath {
    function getSqrtRatioAtTick(int24) internal pure returns (uint160) {
        return uint160(0);
    }
}

contract StableDepositor {
    mapping (address => uint256) public wards;
    mapping (address => uint256) public buds;
    
    DepositorLike public depositor;

    mapping (address => mapping (address => uint256)) public lots;
    mapping (address => mapping (address => uint256)) public counts;
    mapping (address => mapping (address => uint24))  public fees;

    mapping (address => mapping (address => int24)) public tickLowers;
    mapping (address => mapping (address => int24)) public tickUppers;

    mapping (address => mapping (address => int24)) public reqMinTicks; // Assumed within tickLower and tickUpper
    mapping (address => mapping (address => int24)) public reqMaxTicks; // Assumed within tickLower and tickUpper

    bytes32 public immutable ilk;
    address internal immutable uniV3Factory; // 0x1F98431c8aD98523631AE4a59f267346ea31F984

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kissed(address indexed usr);
    event Dissed(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, address indexed src, address indexed dst, uint256 data);
    event File(bytes32 indexed what, address indexed src, address indexed dst, int24 data);
    event Deposit(address indexed src, address indexed dst, uint256 liquidity, uint256 amtSrc, uint256 amtDst);
    event Withdraw(address indexed src, address indexed dst, uint256 liquidity, uint256 amtSrc, uint256 amtDst);

    constructor(bytes32 ilk_, address uniV3Factory_) {
        ilk = ilk_;
        uniV3Factory = uniV3Factory_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth { require(wards[msg.sender] == 1, "StableDepositor/not-authorized"); _; }
    modifier toll { require(buds[msg.sender] == 1, "StableDepositor/non-keeper"); _; }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    function kiss(address usr) external auth {  buds[usr] = 1; emit Kissed(usr); }
    function diss(address usr) external auth {  buds[usr] = 0; emit Dissed(usr); }

    function file(bytes32 what, address data) external auth {
        if (what == "depositor") depositor = DepositorLike(data);
        else revert("StableDepositor/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address src, address dst, uint256 data) external auth {
        if      (what == "lot")   lots[src][dst]   = data;
        else if (what == "count") counts[src][dst] = data;
        else revert("StableDepositor/file-unrecognized-param");
        emit File(what, src, dst, data);
    }

    function file(bytes32 what, address src, address dst, int24 data) external auth {
        if      (what == "tickLower")  tickLowers[src][dst]  = int24(data);
        else if (what == "tickUpper")  tickUppers[src][dst]  = int24(data);
        else if (what == "reqMinTick") reqMinTicks[src][dst] = int24(data);
        else if (what == "reqMaxTick") reqMaxTicks[src][dst] = int24(data);
        else revert("StableDepositor/file-unrecognized-param");
        emit File(what, src, dst, data);
    }

    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function getPoolAddress(address gem0, address gem1, uint24 fee) internal view returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniV3Factory,
            keccak256(abi.encode(gem0, gem1, fee)),
            bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
        )))));
    }

    // TODO: do we want to let the keeper set minTick, maxTick like in the current swapper? (then we need to pass lot as well)
    struct StableDepositorParams {
        address src;
        address dst;
        address swapperCallee;
        bytes swapperData;
    }

    function deposit(StableDepositorParams memory p) toll external returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        address _src = p.src;
        address _dst = p.dst;

        uint256 _cnt = counts[_src][_dst];
        require(_cnt > 0, "StableDepositor/exceeds-count");
        counts[_src][_dst] = _cnt - 1;

        (address _gem0, address _gem1) = (_src < _dst) ? (_src, _dst) : (_dst, _src);
        uint24 _fees = fees[_src][_dst];
        (, int24 _tick,,,,,) = UniV3PoolLike(getPoolAddress(_gem0, _gem1, _fees)).slot0();
        require(_tick >= reqMinTicks[_src][_dst], "StableDepositor/price-below-min");
        require(_tick <= reqMaxTicks[_src][_dst], "StableDepositor/price-above-max");

        uint256 _lot = lots[_src][_dst];
        DepositorLike.DepositParams memory depositParams = DepositorLike.DepositParams({
            gem0     : _gem0,
            gem1     : _gem1,
            amt0     : (_src < _dst) ? _lot : type(uint256).max,
            amt1     : (_src < _dst) ? type(uint256).max : _lot,
            minAmt0  : 0,
            minAmt1  : 0,
            fee      : _fees,
            tickLower: tickLowers[_src][_dst],
            tickUpper: tickUppers[_src][_dst]
        });
        (liquidity, amt0, amt1) = depositor.deposit(depositParams);

        emit Deposit(
            _src,
            _dst,
            liquidity,
            (_src < _dst) ? amt0 : amt1,
            (_src < _dst) ? amt1 : amt0
        );
    }

    function withdraw(StableDepositorParams memory p) toll external returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        address _src = p.src;
        address _dst = p.dst;

        uint256 _cnt = counts[_src][_dst];
        require(_cnt > 0, "StableDepositor/exceeds-count");
        counts[_src][_dst] = _cnt - 1;

        (address _gem0, address _gem1) = (_src < _dst) ? (_src, _dst) : (_dst, _src);
        (uint160 _sqrtPriceX96, int24 _tick,,,,,) = UniV3PoolLike(getPoolAddress(_gem0, _gem1, fees[_src][_dst])).slot0();
        require(_tick >= reqMinTicks[_src][_dst], "StableDepositor/price-below-min");
        require(_tick <= reqMaxTicks[_src][_dst], "StableDepositor/price-above-max");

        // TODO: check if this makes sense
        uint256 _lot = lots[_src][_dst];
        if (_src < _dst) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLowers[_src][_dst]),
                _sqrtPriceX96,
                _lot);
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(
                _sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickUppers[_src][_dst]),
                _lot
            );
        }

        DepositorLike.WithdrawParams memory withdrawParams = DepositorLike.WithdrawParams({
            gem0     : _gem0,
            gem1     : _gem1,
            liquidity: liquidity,
            minAmt0  : (_src < _dst) ? _lot : uint256(0),
            minAmt1  : (_src < _dst) ? uint256(0) : _lot,
            fee      : fees[_src][_dst],
            tickLower: tickLowers[_src][_dst],
            tickUpper: tickUppers[_src][_dst]
        });
        (amt0, amt1) = depositor.withdraw(withdrawParams);

        emit Withdraw(
            _src,
            _dst,
            liquidity,
            (_src < _dst) ? amt0 : amt1,
            (_src < _dst) ? amt1 : amt0
        );
    }
}
