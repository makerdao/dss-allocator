// AllocatorRegistry.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buffers(bytes32) external returns (address) envfree;
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    bytes32 anyBytes32;

    mathint wardsOtherBefore = wards(other);
    address buffersBefore = buffers(anyBytes32);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address buffersAfter = buffers(anyBytes32);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert buffersAfter == buffersBefore, "rely did not keep unchanged every buffers[x]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;
    bytes32 anyBytes32;

    mathint wardsOtherBefore = wards(other);
    address buffersBefore = buffers(anyBytes32);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address buffersAfter = buffers(anyBytes32);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert buffersAfter == buffersBefore, "deny did not keep unchanged every buffers[x]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 ilk, bytes32 what, address data) {
    env e;

    address anyAddr;
    bytes32 otherBytes32;
    require otherBytes32 != ilk;

    mathint wardsBefore = wards(anyAddr);
    address buffersOtherBefore = buffers(otherBytes32);

    file(e, ilk, what, data);

    mathint wardsAfter = wards(anyAddr);
    address buffersIlkAfter = buffers(ilk);
    address buffersOtherAfter = buffers(otherBytes32);

    assert wardsAfter == wardsBefore, "file did not keep unchanged every wards[x]";
    assert buffersIlkAfter == data, "file did not set buffers[ilk] to data";
    assert buffersOtherAfter == buffersOtherBefore, "file did not keep unchanged the rest of buffers[x]";
}

// Verify revert rules on file
rule file_revert(bytes32 ilk, bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, ilk, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x6275666665720000000000000000000000000000000000000000000000000000);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases";
}
