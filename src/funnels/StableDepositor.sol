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
    function getLiquidityForAmounts(
        uint160,
        uint160,
        uint160,
        uint256,
        uint256
    ) internal pure returns (uint128 liquidity) {
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

    mapping (address => mapping (address => Pair))   public pairs;
    mapping (address => mapping (address => Amount)) public amounts;

    bytes32 public immutable ilk;
    address internal immutable uniV3Factory; // 0x1F98431c8aD98523631AE4a59f267346ea31F984

    struct Pair {
        uint16 count;
        uint24 fee;
        int24  tickLower;
        int24  tickUpper;
    }

    struct Amount {
        uint128 amt0;
        uint128 amt1;
        uint128 minAmt0;
        uint128 minAmt1;
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kissed(address indexed usr);
    event Dissed(address indexed usr);
    event File(bytes32 indexed what, address data);

    event File(bytes32 indexed what, address indexed gem0, address indexed gem1, uint16 data);

    event File(bytes32 indexed what, address indexed gem0, address indexed gem1, int24 data);
    event Deposit(address indexed gem0, address indexed gem1, uint256 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed gem0, address indexed gem1, uint256 liquidity, uint256 amt0, uint256 amt1);

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

    function file(bytes32 what, address gem0, address gem1, uint16 data) external auth {
        (gem0, gem1) = gem0 < gem1 ? (gem0, gem1) : (gem1, gem0);
        if (what == "count") pairs[gem0][gem1].count = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data);
    }

    function file(bytes32 what, address gem0, address gem1, uint16 data) external auth {
        (gem0, gem1) = gem0 < gem1 ? (gem0, gem1) : (gem1, gem0);
        if (what == "count") pairs[gem0][gem1].count = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data);
    }

    /*
    function file(bytes32 what, address gem0, address gem1, uint256 data) external auth {
        (gem0, gem1) = gem0 < gem1 ? (gem0, gem1) : (gem1, gem0);
        if      (what == "lot")   lots[gem0][gem1]   = data;
        else if (what == "count") counts[gem0][gem1] = data; // TODO: add missing files
        else revert("StableDepositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data);
    }

    function file(bytes32 what, address gem0, address gem1, int24 data) external auth {
        (gem0, gem1) = gem0 < gem1 ? (gem0, gem1) : (gem1, gem0);
        if      (what == "tickLower")  tickLowers[gem0][gem1]  = int24(data);
        else if (what == "tickUpper")  tickUppers[gem0][gem1]  = int24(data);
        else revert("StableDepositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data);
    }
*/
    // TODO: can extract to library and share with other contracts
    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function getPoolAddress(address gem0, address gem1, uint24 fee) internal view returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniV3Factory,
            keccak256(abi.encode(gem0, gem1, fee)),
            bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
        )))));
    }

    struct StableDepositorParams {
        address gem0;
        address gem1;
    }

    function deposit(StableDepositorParams memory p) toll external returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        address _gem0 = p.gem0;
        address _gem1 = p.gem1;

        Pair memory pair = pairs[_gem0][_gem1];
        uint16 _count    = pair.count;
        require(_count > 0, "StableDepositor/exceeds-count");
        pair.count = _count - 1;
        pairs[_gem0][_gem1] = pair;

        Amount memory amount = amounts[_gem0][_gem1];
        DepositorLike.DepositParams memory depositParams = DepositorLike.DepositParams({
            gem0     : _gem0,
            gem1     : _gem1,
            amt0     : amount.amt0,
            amt1     : amount.amt1,
            minAmt0  : amount.minAmt0,
            minAmt1  : amount.minAmt1,
            fee      : pair.fee,
            tickLower: pair.tickLower,
            tickUpper: pair.tickUpper
        });
        (liquidity, amt0, amt1) = depositor.deposit(depositParams);

        emit Deposit(_gem0, _gem1, liquidity, amt0, amt1);
    }

    function withdraw(StableDepositorParams memory p) toll external returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        address _gem0 = p.gem0;
        address _gem1 = p.gem1;

        Pair memory pair = pairs[_gem0][_gem1];
        uint16 _count    = pair.count;
        require(_count > 0, "StableDepositor/exceeds-count");
        pair.count = _count - 1;
        pairs[_gem0][_gem1] = pair;

        uint24 _fee = pair.fee;
        (uint160 _sqrtPriceX96,,,,,,) = UniV3PoolLike(getPoolAddress(_gem0, _gem1, _fee)).slot0();

        int24 _tickLower = pair.tickLower;
        int24 _tickUpper = pair.tickUpper;
        Amount memory amount = amounts[_gem0][_gem1];
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            amount.amt0,
            amount.amt1
        );

        DepositorLike.WithdrawParams memory withdrawParams = DepositorLike.WithdrawParams({
            gem0     : _gem0,
            gem1     : _gem1,
            liquidity: liquidity,
            minAmt0  : amount.minAmt0,
            minAmt1  : amount.minAmt1,
            fee      : _fee,
            tickLower: _tickLower,
            tickUpper: _tickUpper
        });
        (amt0, amt1) = depositor.withdraw(withdrawParams);

        emit Withdraw(_gem0, _gem1, liquidity, amt0, amt1);
    }
}
