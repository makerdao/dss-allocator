// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function decimals() external view returns (uint8);
}

contract KegMock {
    constructor(address gem) {
        GemLike(gem).approve(msg.sender, type(uint256).max);
    }
}

contract PsmMock {
    mapping(address => uint256) public wards;

    address public immutable dai;
    address public immutable gem;
    uint256 public immutable to18ConversionFactor;
    address public immutable keg;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SellGem(address indexed owner, uint256 value, uint256 fee);
    event BuyGem(address indexed owner, uint256 value, uint256 fee);

    modifier auth() {
        require(wards[msg.sender] == 1, "PsmMock/not-authorized");
        _;
    }

    constructor(address dai_, address gem_) {
        dai = dai_;
        gem = gem_;
        to18ConversionFactor = 10**(18 - GemLike(gem_).decimals());
        keg = address(new KegMock(gem_));

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function sellGemNoFee(address usr, uint256 gemAmt) external auth returns (uint256 daiOutWad) {
        daiOutWad = gemAmt * to18ConversionFactor;

        GemLike(gem).transferFrom(msg.sender, keg, gemAmt);
        GemLike(dai).transfer(usr, daiOutWad);

        emit SellGem(usr, gemAmt, 0);
    }

    function buyGemNoFee(address usr, uint256 gemAmt) external auth returns (uint256 daiInWad) {
        daiInWad = gemAmt * to18ConversionFactor;

        GemLike(dai).transferFrom(msg.sender, address(this), daiInWad);
        GemLike(gem).transferFrom(keg, usr, gemAmt);

        emit BuyGem(usr, gemAmt, 0);
    }
}