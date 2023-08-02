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
    function gemJoin() external view returns (address);
    function ilk() external view returns (bytes32);
}

interface GemJoinLike {
    function gem() external view returns (GemLike);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface BufferLike {
    function approve(address, address, uint256) external;
}

interface VatLike {
    function live() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

contract AllocatorRedeemer {
    // --- storage variables ---

    mapping (address => uint256) public bag;
    mapping (address => mapping (address => uint256)) public out;
    mapping (address => uint256) public totOut;

    // --- immutables ---

    VatLike immutable public vat;
    address immutable public vault;
    address immutable public buffer;
    bytes32 immutable public ilk;
    GemLike immutable public gem;

    // --- constants ---

    uint256 constant WAD = 10**18;

    // --- events ---

    event Pull(address indexed asset, uint256 amt);
    event Pack(address indexed sender, uint256 wad);
    event Cash(address indexed asset, address indexed sender, uint256 wad);

    // --- constructor ---

    constructor(address vat_, address vault_, address buffer_) {
        vat = VatLike(vat_);
        vault = vault_;
        buffer = buffer_;
        ilk = AllocatorVaultLike(vault).ilk();
        gem = GemJoinLike(AllocatorVaultLike(vault).gemJoin()).gem();
    }

    // --- functions ---

    function pull(address asset) external {
        require(vat.live() == 0, "AllocatorRedeemer/system-live");
        uint256 amt = GemLike(asset).balanceOf(buffer);
        BufferLike(buffer).approve(asset, address(this), amt);
        GemLike(asset).transferFrom(buffer, address(this), amt);
        emit Pull(asset, amt);
    }

    function pack(uint256 wad) external {
        require(wad > 0, "AllocatorRedeemer/wad-zero");
        gem.transferFrom(msg.sender, address(this), wad);
        bag[msg.sender] += wad;
        emit Pack(msg.sender, wad);
    }

    // WARNING `cash` should be called after:
    // - the vault urn has been skimmed in the `End` module (otherwise the `totShares` will be wrongly accounted).
    // - the buffer already received the total amount for that asset. In case more value is still expected, cashing before
    //   will mean resigning to that portion of the share. Pending stakeholders will accrue it.
    // - all receving funds in the buffer are previously pulled to this contract.
    function cash(address asset, uint256 wad) external {
        require(wad > 0, "AllocatorRedeemer/wad-zero");
        (uint256 ink,) = vat.urns(ilk, vault);
        uint256 totShares = gem.totalSupply() - ink;
        uint256 totOut_   = totOut[asset];
        totOut[asset]    += wad;
        uint256 out_      = out[asset][msg.sender] += wad;
        require(out_ <= bag[msg.sender], "AllocatorRedeemer/insufficient-bag-balance");
        GemLike(asset).transfer(msg.sender, wad * GemLike(asset).balanceOf(address(this)) / (totShares - totOut_));
        emit Cash(asset, msg.sender, wad);
    }
}
