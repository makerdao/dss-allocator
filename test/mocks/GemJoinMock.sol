// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import { VatMock } from "test/mocks/VatMock.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract GemJoinMock {
    VatMock public vat;
    bytes32 public ilk;
    GemMock public gem;

    constructor(VatMock vat_, bytes32 ilk_, GemMock gem_) {
        vat = vat_;
        ilk = ilk_;
        gem = gem_;
    }

    function join(address usr, uint256 wad) external {
        vat.slip(ilk, usr, int256(wad));
        gem.transferFrom(msg.sender, address(this), wad);
    }
}
