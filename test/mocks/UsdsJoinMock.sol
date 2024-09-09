// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import { VatMock } from "test/mocks/VatMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract UsdsJoinMock {
    VatMock public vat;
    GemMock public usds;

    constructor(VatMock vat_, GemMock usds_) {
        vat  = vat_;
        usds = usds_;
    }

    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, wad * 10**27);
        usds.burn(msg.sender, wad);
    }

    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), wad * 10**27);
        usds.mint(usr, wad);
    }
}
