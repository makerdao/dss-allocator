// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import { VatMock } from "test/mocks/VatMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract NstJoinMock {
    VatMock public vat;
    GemMock public nst;

    constructor(VatMock vat_, GemMock nst_) {
        vat = vat_;
        nst = nst_;
    }

    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, wad * 10**27);
        nst.burn(msg.sender, wad);
    }

    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), wad * 10**27);
        nst.mint(usr, wad);
    }
}
