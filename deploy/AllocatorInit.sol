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

pragma solidity >=0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { DssInstance } from "dss-test/MCD.sol";
import { AllocatorSharedInstance, AllocatorIlkInstance } from "./AllocatorInstances.sol";

interface WardsLike {
    function rely(address) external;
    function deny(address) external;
}

interface IlkRegistryLike {
    function put(
        bytes32 _ilk,
        address _join,
        address _gem,
        uint256 _dec,
        uint256 _class,
        address _pip,
        address _xlip,
        string calldata _name,
        string calldata _symbol
    ) external;
}

interface RolesLike {
    function setIlkAdmin(bytes32, address) external;
    function setUserRole(bytes32, address, uint8, bool) external;
    function setRoleAction(bytes32, uint8, address, bytes4, bool) external;
}

interface RegistryLike {
    function file(bytes32, bytes32, address) external;
}

interface VaultLike {
    function ilk() external view returns (bytes32);
    function roles() external view returns (address);
    function buffer() external view returns (address);
    function vat() external view returns (address);
    function nst() external view returns (address);
    function file(bytes32, address) external;
    function draw(uint256) external;
    function wipe(uint256) external;
}

interface BufferLike {
    function approve(address, address, uint256) external;
}

interface SwapperLike {
    function roles() external view returns (address);
    function ilk() external view returns (bytes32);
    function buffer() external view returns (address);
    function swap(address, address, uint256, uint256, address, bytes calldata) external returns (uint256);
}

interface DepositorUniV3Like {
    struct LiquidityParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 liquidity;
        uint256 amt0Desired;
        uint256 amt1Desired;
        uint256 amt0Min;
        uint256 amt1Min;
    }

    struct CollectParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
    }

    function roles() external view returns (address);
    function ilk() external view returns (bytes32);
    function buffer() external view returns (address);
    function deposit(LiquidityParams memory) external returns (uint128, uint256, uint256);
    function withdraw(LiquidityParams memory, bool) external returns (uint128, uint256, uint256, uint256, uint256);
    function collect(CollectParams memory) external returns (uint256, uint256);
}

interface StableSwapperLike {
    function swapper() external view returns (address);
}

interface StableDepositorUniV3Like {
    function depositor() external view returns (address);
}

interface ConduitMoverLike {
    function ilk() external view returns (bytes32);
    function buffer() external view returns (address);
}

interface KissLike {
    function kiss(address) external;
}

struct AllocatorIlkConfig {
    bytes32 ilk;
    uint256 duty;
    uint256 debtCeiling;
    address allocatorProxy;
    uint8 facilitatorRole;
    uint8 automationRole;
    address[] facilitators;
    address[] stableSwapperKeepers;
    address[] stableDepositorUniV3Keepers;
    address[] conduitMoverKeepers;
    address[] swapTokens;
    address[] depositTokens;
    address ilkRegistry;
}

function bytes32ToStr(bytes32 _bytes32) pure returns (string memory) {
    uint256 len;
    while(len < 32 && _bytes32[len] != 0) len++;
    bytes memory bytesArray = new bytes(len);
    for (uint256 i; i < len; i++) {
        bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
}

library AllocatorInit {
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    uint256 constant RATES_ONE_HUNDRED_PCT = 1000000021979553151239153027;

    function initShared(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance
    ) internal {
        dss.chainlog.setAddress("ALLOCATOR_ROLES",    sharedInstance.roles);
        dss.chainlog.setAddress("ALLOCATOR_REGISTRY", sharedInstance.registry);
    }

    function initIlk(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance,
        AllocatorIlkInstance memory ilkInstance,
        AllocatorIlkConfig memory cfg
    ) internal {
        bytes32 ilk = cfg.ilk;

        // Sanity checks
        require(VaultLike(ilkInstance.vault).ilk()    == ilk,                  "AllocatorInit/vault-ilk-mismatch");
        require(VaultLike(ilkInstance.vault).roles()  == sharedInstance.roles, "AllocatorInit/vault-roles-mismatch");
        require(VaultLike(ilkInstance.vault).buffer() == ilkInstance.buffer,   "AllocatorInit/vault-buffer-mismatch");
        require(VaultLike(ilkInstance.vault).vat()    == address(dss.vat),     "AllocatorInit/vault-vat-mismatch");
        // Once nstJoin is in the chainlog and adapted to dss-test should also check against it

        require(SwapperLike(ilkInstance.swapper).roles()  == sharedInstance.roles, "AllocatorInit/swapper-roles-mismatch");
        require(SwapperLike(ilkInstance.swapper).ilk()    == ilk,                  "AllocatorInit/swapper-ilk-mismatch");
        require(SwapperLike(ilkInstance.swapper).buffer() == ilkInstance.buffer,   "AllocatorInit/swapper-buffer-mismatch");

        require(DepositorUniV3Like(ilkInstance.depositorUniV3).roles()  == sharedInstance.roles, "AllocatorInit/depositorUniV3-roles-mismatch");
        require(DepositorUniV3Like(ilkInstance.depositorUniV3).ilk()    == ilk,                  "AllocatorInit/depositorUniV3-ilk-mismatch");
        require(DepositorUniV3Like(ilkInstance.depositorUniV3).buffer() == ilkInstance.buffer,   "AllocatorInit/depositorUniV3-buffer-mismatch");

        require(StableSwapperLike(ilkInstance.stableSwapper).swapper()                 == ilkInstance.swapper,        "AllocatorInit/stableSwapper-swapper-mismatch");
        require(StableDepositorUniV3Like(ilkInstance.stableDepositorUniV3).depositor() == ilkInstance.depositorUniV3, "AllocatorInit/stableDepositorUniV3-depositorUniV3-mismatch");

        require(ConduitMoverLike(ilkInstance.conduitMover).ilk()    == ilk,                "AllocatorInit/conduitMover-ilk-mismatch");
        require(ConduitMoverLike(ilkInstance.conduitMover).buffer() == ilkInstance.buffer, "AllocatorInit/conduitMover-buffer-mismatch");

        // Onboard the ilk
        dss.vat.init(ilk);
        dss.jug.init(ilk);

        require((cfg.duty >= RAY) && (cfg.duty <= RATES_ONE_HUNDRED_PCT), "AllocatorInit/ilk-duty-out-of-bounds");
        dss.jug.file(ilk, "duty", cfg.duty);

        require(cfg.debtCeiling < WAD, "AllocatorInit/incorrect-ilk-line-precision");
        dss.vat.file(ilk, "line", cfg.debtCeiling * RAD);
        dss.vat.file("Line", dss.vat.Line() + cfg.debtCeiling * RAD);

        dss.spotter.file(ilk, "pip", sharedInstance.oracle);
        dss.spotter.file(ilk, "mat", RAY);
        dss.spotter.poke(ilk);

        // Add buffer to registry
        RegistryLike(sharedInstance.registry).file(ilk, "buffer", ilkInstance.buffer);

        // Initiate the allocator vault
        dss.vat.slip(ilk, ilkInstance.vault, int256(1_000_000 * WAD));
        dss.vat.grab(ilk, ilkInstance.vault, ilkInstance.vault, address(0), int256(1_000_000 * WAD), 0);

        VaultLike(ilkInstance.vault).file("jug", address(dss.jug));

        // Allow vault and funnels to pull funds from the buffer
        BufferLike(ilkInstance.buffer).approve(VaultLike(ilkInstance.vault).nst(), ilkInstance.vault, type(uint256).max);
        for(uint256 i = 0; i < cfg.swapTokens.length; i++) {
            BufferLike(ilkInstance.buffer).approve(cfg.swapTokens[i], ilkInstance.swapper, type(uint256).max);
        }
        for(uint256 i = 0; i < cfg.depositTokens.length; i++) {
            BufferLike(ilkInstance.buffer).approve(cfg.depositTokens[i], ilkInstance.depositorUniV3, type(uint256).max);
        }

        // Set the pause proxy temporarily as ilk admin so we can set all the roles below
        RolesLike(sharedInstance.roles).setIlkAdmin(ilk, ilkInstance.owner);

        // Allow the facilitators to operate on the vault and funnels directly
        for(uint256 i = 0; i < cfg.facilitators.length; i++) {
            RolesLike(sharedInstance.roles).setUserRole(ilk, cfg.facilitators[i], cfg.facilitatorRole, true);
        }

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.vault,          VaultLike.draw.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.vault,          VaultLike.wipe.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.swapper,        SwapperLike.swap.selector,            true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.depositorUniV3, DepositorUniV3Like.deposit.selector,  true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.depositorUniV3, DepositorUniV3Like.collect.selector,  true);

        // Allow the automation contracts to operate on the funnels
        RolesLike(sharedInstance.roles).setUserRole(ilk, ilkInstance.stableSwapper,        cfg.automationRole, true);
        RolesLike(sharedInstance.roles).setUserRole(ilk, ilkInstance.stableDepositorUniV3, cfg.automationRole, true);

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.swapper,        SwapperLike.swap.selector,            true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.depositorUniV3, DepositorUniV3Like.deposit.selector,  true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.depositorUniV3, DepositorUniV3Like.collect.selector,  true);

        // Set the allocator proxy as the ilk admin instead of the Pause Proxy
        RolesLike(sharedInstance.roles).setIlkAdmin(ilk, cfg.allocatorProxy);

        // Allow facilitator to set configurations in the automation contracts
        for(uint256 i = 0; i < cfg.facilitators.length; i++) {
            WardsLike(ilkInstance.stableSwapper).rely(cfg.facilitators[i]);
            WardsLike(ilkInstance.stableDepositorUniV3).rely(cfg.facilitators[i]);
            WardsLike(ilkInstance.conduitMover).rely(cfg.facilitators[i]);
        }

        // Add keepers to the automation contracts
        for(uint256 i = 0; i < cfg.stableSwapperKeepers.length; i++) {
            KissLike(ilkInstance.stableSwapper).kiss(cfg.stableSwapperKeepers[i]);
        }
        for(uint256 i = 0; i < cfg.stableDepositorUniV3Keepers.length; i++) {
            KissLike(ilkInstance.stableDepositorUniV3).kiss(cfg.stableDepositorUniV3Keepers[i]);
        }
        for(uint256 i = 0; i < cfg.conduitMoverKeepers.length; i++) {
            KissLike(ilkInstance.conduitMover).kiss(cfg.conduitMoverKeepers[i]);
        }

        // Move ownership of the ilk contracts to the allocator proxy
        ScriptTools.switchOwner(ilkInstance.vault,                ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.buffer,               ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.swapper,              ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.depositorUniV3,       ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.stableSwapper,        ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.stableDepositorUniV3, ilkInstance.owner, cfg.allocatorProxy);
        ScriptTools.switchOwner(ilkInstance.conduitMover,         ilkInstance.owner, cfg.allocatorProxy);

        // Add allocator-specific contracts to changelog
        string memory ilkString = ScriptTools.ilkToChainlogFormat(ilk);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked(ilkString, "_VAULT"))),  ilkInstance.vault);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked(ilkString, "_BUFFER"))), ilkInstance.buffer);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked("PIP_", ilkString))), sharedInstance.oracle);

        // Add to ilk registry
        IlkRegistryLike(cfg.ilkRegistry).put({
            _ilk    : ilk,
            _join   : address(0),
            _gem    : address(0),
            _dec    : 0,
            _class  : 5, // RWAs are class 3, D3Ms and Teleport are class 4
            _pip    : sharedInstance.oracle,
            _xlip   : address(0),
            _name   : bytes32ToStr(ilk),
            _symbol : bytes32ToStr(ilk)
        });
    }
}
