// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/Swapper.sol";
import "../../funnels/Escrow.sol";
import "dss-test/DssTest.sol";

interface TransferLike {
    function transfer(address, uint256) external returns (bool);
}

contract BufferMock {
    address immutable dai;
    constructor(address _dai) {
        dai = _dai;
    }
    function take(address to, uint256 wad) external {
        TransferLike(dai).transfer(to, wad);
    }
}


contract SwapperTest is DssTest {
    Swapper public swapper;

    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);

    function setUp() public {
        swapper = new Swapper(DAI, USDC, UNIV3_ROUTER, 100);
        address escrow = address(new Escrow());
        Escrow(escrow).approve(USDC, address(swapper), type(uint256).max);
        address buffer = address(new BufferMock(DAI));
        deal(DAI, buffer, 1_000_000_000 ether, true);
        uint256 maxNstLot = 10_000 ether;
        uint256 maxGemLot = 11_000 ether / 10**12;
        swapper.file("escrow", escrow);
        swapper.file("buffer", buffer);
        swapper.file("maxNstLot", maxNstLot);
        swapper.file("maxGemLot", maxGemLot);
        swapper.file("minNstPrice", 99 ether / 100);
        swapper.file("minGemPrice", 99 ether / 100);
        swapper.kiss(FACILITATOR);
        vm.prank(FACILITATOR); swapper.setLots(maxNstLot, maxGemLot);
        vm.prank(FACILITATOR); swapper.setCounts(1, 1);
        vm.prank(FACILITATOR); swapper.permit(KEEPER);
    }

    function testSwap() public {
        uint256 nstLot = swapper.nstLot();
        vm.prank(KEEPER); uint256 gemOut = swapper.nstToGem(nstLot * 995/1000 / 10**12);
        console2.log("gemOut:", gemOut * 10**12);

        vm.prank(FACILITATOR); swapper.setLots(nstLot, gemOut);
        vm.prank(KEEPER); uint256 daiOut = swapper.gemToNst(gemOut * 995/1000 * 10**12);
        console2.log("daiOut:", daiOut);
    }

}
