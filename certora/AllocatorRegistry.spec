// AllocatorRegistry.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function buffers(bytes32) external returns (address) envfree;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;
    bytes32 anyBytes32;

    mathint wardsBefore = wards(anyAddr);
    address buffersBefore = buffers(anyBytes32);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address buffersAfter = buffers(anyBytes32);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert buffersAfter != buffersBefore => f.selector == sig:file(bytes32,bytes32,address).selector, "buffers[x] changed in an unexpected function";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting file
rule file(bytes32 ilk, bytes32 what, address data) {
    env e;

    bytes32 otherBytes32;
    require otherBytes32 != ilk;

    address buffersOtherBefore = buffers(otherBytes32);

    file(e, ilk, what, data);

    address buffersIlkAfter = buffers(ilk);
    address buffersOtherAfter = buffers(otherBytes32);

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

    assert lastReverted <=> revert1 || revert2 || revert3, "Revert rules failed";
}
