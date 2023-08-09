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

interface ConduitLike {
    function deposit(bytes32, address, uint256) external;
    function withdraw(bytes32, address, uint256) external;
}

contract ConduitMover {
    mapping (address => uint256) public wards;                                                // Admins
    mapping (address => uint256) public buds;                                                 // Whitelisted keepers
    mapping (address => mapping (address => mapping (address => MoveConfig))) public configs; // Configuration for keepers

    bytes32 public immutable ilk;    // Collateral type
    address public immutable buffer; // The address of the buffer contract

    struct MoveConfig {
        uint64   num; // The remaining number of times that a `from` to `to` gem move can be performed by keepers
        uint32   hop; // Cooldown period it has to wait between `from` to `to` gem moves
        uint32   zzz; // Timestamp of the last `from` to `to` gem move
        uint128  lot; // The amount to move every hop for a `from` to `to` gem move
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed from, address indexed to, address indexed gem, uint64 num, uint32 hop, uint128 lot);
    event Move(address indexed from, address indexed to, address indexed gem, uint128 lot);

    constructor(bytes32 ilk_, address buffer_) {
        buffer = buffer_;
        ilk    = ilk_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "ConduitMover/not-authorized");
        _;
    }

    modifier toll {
        require(buds[msg.sender] == 1, "ConduitMover/non-keeper");
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

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function setConfig(address from, address to, address gem, uint64 num, uint32 hop, uint128 lot) external auth {
        configs[from][to][gem] = MoveConfig({
            num: num,
            hop: hop,
            zzz: 0,
            lot: lot
        });
        emit SetConfig(from, to, gem, num, hop, lot);
    }

    function move(address from, address to, address gem) toll external {
        MoveConfig memory cfg = configs[from][to][gem];

        require(cfg.num > 0, "ConduitMover/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "ConduitMover/too-soon");
        unchecked { configs[from][to][gem].num = cfg.num - 1; }
        configs[from][to][gem].zzz = uint32(block.timestamp);

        if (from != buffer) ConduitLike(from).withdraw(ilk, gem, cfg.lot);
        if (to   != buffer) ConduitLike(to).deposit(ilk, gem, cfg.lot);

        emit Move(from, to, gem, cfg.lot);
    }
}
