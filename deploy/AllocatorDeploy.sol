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
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { AllocatorOracle }   from "src/AllocatorOracle.sol";
import { AllocatorRoles }    from "src/AllocatorRoles.sol";
import { AllocatorRegistry } from "src/AllocatorRegistry.sol";
import { AllocatorBuffer }   from "src/AllocatorBuffer.sol";
import { AllocatorVault }    from "src/AllocatorVault.sol";

import { AllocatorSharedInstance, AllocatorIlkInstance } from "./AllocatorInstances.sol";

library AllocatorDeploy {

    // Note: owner is assumed to be the pause proxy
    function deployShared(
        address deployer,
        address owner
    ) internal returns (AllocatorSharedInstance memory sharedInstance) {
        address _oracle = address(new AllocatorOracle());

        address _roles  = address(new AllocatorRoles());
        ScriptTools.switchOwner(_roles, deployer, owner);

        address _registry = address(new AllocatorRegistry());
        ScriptTools.switchOwner(_registry, deployer, owner);

        sharedInstance.oracle   = _oracle;
        sharedInstance.roles    = _roles;
        sharedInstance.registry = _registry;
    }

    // Note: owner is assumed to be the pause proxy, allocator proxy will receive ownerships on init
    function deployIlk(
        address deployer,
        address owner,
        address roles,
        bytes32 ilk,
        address nstJoin
    ) internal returns (AllocatorIlkInstance memory ilkInstance) {
        address _buffer = address(new AllocatorBuffer());
        ScriptTools.switchOwner(_buffer, deployer, owner);
        ilkInstance.buffer = _buffer;

        address _vault  = address(new AllocatorVault(roles, _buffer, ilk, nstJoin));
        ScriptTools.switchOwner(_vault, deployer, owner);
        ilkInstance.vault = _vault;

        ilkInstance.owner = owner;
    }
}
