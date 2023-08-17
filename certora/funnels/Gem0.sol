// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import { GemMock } from "test/mocks/GemMock.sol";

contract Gem0 is GemMock(1_000_000*10**18) {
}
