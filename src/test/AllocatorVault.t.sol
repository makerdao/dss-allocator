// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import "../AllocatorVault.sol";

contract VatMock {
    uint256 public Art;
    uint256 public rate = 10**27;
    uint256 public line = 20_000_000 * 10**45;

    struct Urn {
        uint256 ink;
        uint256 art;
    }

    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public gem;
    mapping (address => uint256)                   public dai;

    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (Art, rate, 0, line, 0);
    }

    function hope(address) external {}

    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external {
        Urn memory urn = urns[i][u];

        urn.ink = dink >= 0 ? urn.ink + uint256(dink) : urn.ink - uint256(-dink);
        Art = urn.art = dart >= 0 ? urn.art + uint256(dart) : urn.art - uint256(-dart);

        gem[i][v] = dink >= 0 ? gem[i][v] - uint256(dink) : gem[i][v] + uint256(-dink);
        int256 dtab = int256(rate) * dart;
        dai[w] = dtab >= 0 ? dai[w] + uint256(dtab) : dai[w] - uint256(-dtab);

        urns[i][u] = urn;
    }

    function move(address src, address dst, uint256 rad) external {
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

contract GemMock {
    mapping (address => uint256)                      public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    uint256 public totalSupply;

    constructor(uint256 initialSupply) {
        mint(msg.sender, initialSupply);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        uint256 balance = balanceOf[msg.sender];
        require(balance >= value, "Gem/insufficient-balance");

        unchecked {
            balanceOf[msg.sender] = balance - value;
            balanceOf[to] += value;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 balance = balanceOf[from];
        require(balance >= value, "Gem/insufficient-balance");

        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "Gem/insufficient-allowance");

                unchecked {
                    allowance[from][msg.sender] = allowed - value;
                }
            }
        }

        unchecked {
            balanceOf[from] = balance - value;
            balanceOf[to] += value;
        }
        return true;
    }

    function mint(address to, uint256 value) public {
        unchecked {
            balanceOf[to] = balanceOf[to] + value;
        }
        totalSupply = totalSupply + value;
    }

    function burn(address from, uint256 value) external {
        uint256 balance = balanceOf[from];
        require(balance >= value, "Gem/insufficient-balance");

        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "Gem/insufficient-allowance");

                unchecked {
                    allowance[from][msg.sender] = allowed - value;
                }
            }
        }

        unchecked {
            balanceOf[from] = balance - value;
            totalSupply     = totalSupply - value;
        }
    }
}

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

contract AllocatorVaultTest is DssTest {
    using stdStorage for StdStorage;

    VatMock         public vat;
    JugMock         public jug;
    GemMock         public gem;
    GemJoinMock     public gemJoin;
    GemMock         public nst;
    NstJoinMock     public nstJoin;
    AllocatorVault  public vault;
    bytes32         public ilk;

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function setUp() public {
        ilk     = "TEST-ILK";
        vat     = new VatMock();
        jug     = new JugMock(vat);
        gem     = new GemMock(1_000_000 * 10**18);
        gemJoin = new GemJoinMock(vat, ilk, gem);
        nst     = new GemMock(0);
        nstJoin = new NstJoinMock(vat, nst);
        vault   = new AllocatorVault(address(vat), address(gemJoin), address(nstJoin));
        gem.transfer(address(vault), 1_000_000 * 10**18);

        // Add some existing DAI assigned to nstJoin to avoid a particular error
        stdstore.target(address(vat)).sig("dai(address)").with_key(address(nstJoin)).depth(0).checked_write(100_000 * 10**45);
    }

    function testAuth() public {
        checkAuth(address(vault), "AllocatorVault");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](5);
        authedMethods[0] = vault.init.selector;
        authedMethods[1] = bytes4(keccak256("draw(address,uint256)"));
        authedMethods[2] = bytes4(keccak256("draw(uint256)"));
        authedMethods[3] = vault.take.selector;
        authedMethods[4] = vault.wipe.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(vault), "AllocatorVault/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testFile() public {
        checkFileAddress(address(vault), "AllocatorVault", ["jug"]);
    }

    function testInit() public {
        assertEq(gem.balanceOf(address(vault)),  gem.totalSupply());
        assertEq(gem.balanceOf(address(gemJoin)), 0);
        (uint256 ink, ) = vat.urns(ilk, address(vault));
        assertEq(ink, 0);
        vault.init();
        assertEq(gem.balanceOf(address(vault)),  0);
        assertEq(gem.balanceOf(address(gemJoin)), gem.totalSupply());
        (ink, ) = vat.urns(ilk, address(vault));
        assertEq(ink, gem.totalSupply());
    }

    function testInitNotTotalSupply() public {
        deal(address(gem), address(vault), gem.balanceOf(address(vault)) - 1);
        vm.expectRevert("Gem/insufficient-balance");
        vault.init();
    }

    uint256 div = 1001; // Hack to solve a compiling issue

    function testDrawWipe() public {
        vault.init();
        vault.file("jug", address(jug));
        assertEq(vault.line(), 20_000_000 * 10**18);
        (, uint256 art) = vat.urns(ilk, address(vault));
        assertEq(art, 0);
        vault.draw(50 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        assertEq(art, 50 * 10**18);
        assertEq(vat.rate(), 10**27);
        assertEq(vault.debt(), 50 * 10**18);
        assertEq(vault.slot(), vault.line() - 50 * 10**18);
        assertEq(nst.balanceOf(address(vault)), 50 * 10**18);
        vm.warp(block.timestamp + 1);
        vault.draw(50 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        uint256 expectedArt = 50 * 10**18 + _divup(50 * 10**18 * 1000, div);
        assertEq(art, expectedArt);
        assertEq(vat.rate(), 1001 * 10**27 / 1000);
        assertEq(vault.debt(), _divup(expectedArt * 1001, 1000));
        assertEq(vault.slot(), vault.line() - _divup(expectedArt * 1001, 1000));
        assertEq(nst.balanceOf(address(vault)), 100 * 10**18);
        assertGt(art * vat.rate(), 100.05 * 10**45);
        assertLt(art * vat.rate(), 100.06 * 10**45);
        vm.expectRevert("Gem/insufficient-balance");
        vault.wipe(100.06 ether);
        deal(address(nst), address(vault), 100.06 * 10**18, true);
        assertEq(nst.balanceOf(address(vault)), 100.06 * 10**18);
        vm.expectRevert();
        vault.wipe(100.06 ether); // It will try to wipe more art than existing, then reverts
        vault.wipe(100.05 ether);
        assertEq(nst.balanceOf(address(vault)), 0.01 * 10**18);
        (, art) = vat.urns(ilk, address(vault));
        assertEq(art, 1); // Dust which is impossible to wipe
    }

    function testDrawOtherAddress() public {
        vault.init();
        vault.file("jug", address(jug));
        vault.draw(address(0xBEEF), 50 * 10**18);
        assertEq(nst.balanceOf(address(0xBEEF)), 50 * 10**18);
    }

    function testDrawAndTake() public {
        vault.init();
        vault.file("jug", address(jug));
        vault.draw(50 * 10**18);
        assertEq(nst.balanceOf(address(vault)), 50 * 10**18);
        vault.take(address(0xBEEF), 20 * 10**18);
        assertEq(nst.balanceOf(address(vault)), 30 * 10**18);
        assertEq(nst.balanceOf(address(0xBEEF)), 20 * 10**18);
    }

    function testDebtOverLine() public {
        vault.init();
        vault.file("jug", address(jug));
        vault.draw(vault.line());
        vm.warp(block.timestamp + 1);
        jug.drip(ilk);
        assertGt(vault.debt(), vault.line());
        assertEq(vault.slot(), 0);
    }
}
