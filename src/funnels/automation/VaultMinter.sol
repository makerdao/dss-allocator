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

interface AllocatorVaultLike {
    function draw(uint256) external;
    function wipe(uint256) external;
}

contract VaultMinter {
    mapping (address => uint256) public wards; // Admins
    mapping (address => uint256) public buds;  // Whitelisted keepers
    MinterConfig public config;                // Configuration for keepers

    address public immutable vault; // The address of the vault contract

    struct MinterConfig {
        int64    num; // The remaining number of times that a mint or burn can be executed by keepers (> 0: mint, < 0: burn)
        uint32   hop; // Cooldown period it has to wait between each action
        uint32   zzz; // Timestamp of the last action
        uint128  lot; // The amount to mint or burn every hop
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(int64 num, uint32 hop, uint128 lot);
    event Mint(uint128 lot);
    event Burn(uint128 lot);

    constructor(address vault_) {
        vault  = vault_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "VaultMinter/not-authorized");
        _;
    }

    modifier toll {
        require(buds[msg.sender] == 1, "VaultMinter/non-keeper");
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

    function setConfig(int64 num, uint32 hop, uint128 lot) external auth {
        config = MinterConfig({
            num: num,
            hop: hop,
            zzz: 0,
            lot: lot
        });
        emit SetConfig(num, hop, lot);
    }

    function mint() toll external {
        MinterConfig memory cfg = config;

        require(cfg.num > 0, "VaultMinter/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "VaultMinter/too-soon");
        unchecked { config.num = cfg.num - 1; }
        config.zzz = uint32(block.timestamp);

        AllocatorVaultLike(vault).draw(cfg.lot);

        emit Mint(cfg.lot);
    }

    function burn() toll external {
        MinterConfig memory cfg = config;

        require(cfg.num < 0, "VaultMinter/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "VaultMinter/too-soon");
        unchecked { config.num = cfg.num + 1; }
        config.zzz = uint32(block.timestamp);

        AllocatorVaultLike(vault).wipe(cfg.lot);

        emit Burn(cfg.lot);
    }
}
