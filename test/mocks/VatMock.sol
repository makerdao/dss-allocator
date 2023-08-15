// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract VatMock {
    uint256 public Art;
    uint256 public rate = 10**27;
    uint256 public line = 20_000_000 * 10**45;

    struct Urn {
        uint256 ink;
        uint256 art;
    }

    mapping (address => mapping (address => uint256)) public can;
    mapping (bytes32 => mapping (address => Urn ))    public urns;
    mapping (bytes32 => mapping (address => uint))    public gem;
    mapping (address => uint256)                      public dai;

    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (Art, rate, 0, line, 0);
    }

    function hope(address usr) external {
        can[msg.sender][usr] = 1;
    }

    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external {
        require(u == msg.sender || can[u][msg.sender] == 1);
        Urn memory urn = urns[i][u];

        urn.ink = dink >= 0 ? urn.ink + uint256(dink) : urn.ink - uint256(-dink);
        Art = urn.art = dart >= 0 ? urn.art + uint256(dart) : urn.art - uint256(-dart);

        gem[i][v] = dink >= 0 ? gem[i][v] - uint256(dink) : gem[i][v] + uint256(-dink);
        require(dart == 0 || rate <= uint256(type(int256).max));
        int256 dtab = int256(rate) * dart;
        dai[w] = dtab >= 0 ? dai[w] + uint256(dtab) : dai[w] - uint256(-dtab);

        urns[i][u] = urn;
    }

    function move(address src, address dst, uint256 rad) external {
        require(src == msg.sender || can[src][msg.sender] == 1);
        dai[src] = dai[src] - rad;
        dai[dst] = dai[dst] + rad;
    }

    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = wad >= 0 ? gem[ilk][usr] + uint256(wad) : gem[ilk][usr] - uint256(-wad);
    }

    function fold(uint256 rate_) external {
        rate = rate + rate_;
    }
}
