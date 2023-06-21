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

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function live() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface GemJoinLike {
    function gem() external view returns (TokenLike);
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
    function join(address, uint256) external;
}

interface NstJoinLike {
    function nst() external view returns (TokenLike);
    function vat() external view returns (address);
    function exit(address, uint256) external;
    function join(address, uint256) external;
}

contract AllocatorVault {

    // --- storage variables ---

    mapping(address => uint256) public wards;
    JugLike public jug;

    // --- constants ---

    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;

    // --- immutables ---

    RolesLike   immutable public roles;
    address     immutable public buffer;
    VatLike     immutable public vat;
    bytes32     immutable public ilk;
    GemJoinLike immutable public gemJoin;
    NstJoinLike immutable public nstJoin;
    TokenLike   immutable public nst;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Init(uint256 supply);
    event Draw(address indexed sender, address indexed to, uint256 wad);
    event Wipe(address indexed sender, address indexed from, uint256 wad);

    // --- modifiers ---

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) ||
                wards[msg.sender] == 1, "AllocatorVault/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(address roles_, address buffer_, address vat_, address gemJoin_, address nstJoin_) {
        roles = RolesLike(roles_);

        buffer = buffer_;
        vat = VatLike(vat_);

        gemJoin = GemJoinLike(gemJoin_);
        nstJoin = NstJoinLike(nstJoin_);

        require(vat_ == gemJoin.vat() && vat_ == nstJoin.vat(), "AllocatorVault/vat-not-match");

        ilk = GemJoinLike(gemJoin_).ilk();
        nst = NstJoinLike(nstJoin_).nst();

        VatLike(vat_).hope(nstJoin_);
        nst.approve(nstJoin_, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- math ---

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    // --- getters ---
    // In theory, `ilk.Art` should be equal to `urn.art` for this type of collateral, as there should only be one position per `ilk`.
    // However to stick with the correct usage, `ilk.Art` is used for calculating `slot()` and `urn.art` for the `debt()` of this position.

    function debt() external view returns (uint256) {
        (, uint256 art) = vat.urns(ilk, address(this));
        (, uint256 rate,,,) = vat.ilks(ilk);
        return _divup(art * rate, RAY);
    }

    function line() external view returns (uint256) {
        (,,, uint256 line_,) = vat.ilks(ilk);
        return line_ / RAY;
    }

    function slot() external view returns (uint256) {
        (uint256 Art, uint256 rate,, uint256 line_,) = vat.ilks(ilk);
        uint256 debt_ = Art * rate;
        return line_ > debt_ ? (line_ - debt_) / RAY : 0;
    }

    // --- administration ---

    function init() external auth {
        TokenLike gem = gemJoin.gem();
        uint256 supply = gem.totalSupply();
        require(supply == 10**6 * WAD, "AllocatorVault/supply-not-one-million-wad");

        gem.approve(address(gemJoin), supply);
        gemJoin.join(address(this), supply);
        vat.frob(ilk, address(this), address(this), address(0), int256(supply), 0);

        emit Init(supply);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "jug") {
            jug = JugLike(data);
        } else revert("AllocatorVault/file-unrecognized-param");
        emit File(what, data);
    }

    // --- funnels execution ---

    function draw(address to, uint256 wad) public auth {
        uint256 rate = jug.drip(ilk);
        uint256 dart = _divup(wad * RAY, rate);
        require(dart <= uint256(type(int256).max), "AllocatorVault/overflow");
        vat.frob(ilk, address(this), address(0), address(this), 0, int256(dart));
        nstJoin.exit(to, wad);
        emit Draw(msg.sender, to, wad);
    }

    function draw(uint256 wad) external {
        draw(buffer, wad);
    }

    function wipe(address from, uint256 wad) public auth {
        nst.transferFrom(from, address(this), wad);
        nstJoin.join(address(this), wad);
        uint256 rate = jug.drip(ilk);
        uint256 dart = wad * RAY / rate;
        require(dart <= uint256(type(int256).max), "AllocatorVault/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, -int256(dart));
        emit Wipe(msg.sender, from, wad);
    }

    function wipe(uint256 wad) external {
        wipe(buffer, wad);
    }

    // TODO: evaluate if quit function is necessary and how it should be
}
