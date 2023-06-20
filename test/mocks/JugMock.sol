// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import { VatMock } from "test/mocks/VatMock.sol";

contract JugMock {
    VatMock vat;

    uint256 duty = 1001 * 10**27 / 1000;
    uint256 rho = block.timestamp;

    constructor(VatMock vat_) {
        vat = vat_;
    }

    function drip(bytes32) external returns (uint256 rate) {
        uint256 add = (duty - 10**27) * (block.timestamp - rho);
        rate = vat.rate() + add;
        vat.fold(add);
        rho = block.timestamp;
    }
}
