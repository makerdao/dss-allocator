// AllocatorRoles.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function ilkAdmins(bytes32) external returns (address) envfree;
    function userRoles(bytes32, address) external returns (bytes32) envfree;
    function actionsRoles(bytes32, address, bytes4) external returns (bytes32) envfree;
    function hasUserRole(bytes32, address, uint8) external returns (bool) envfree;
    function hasActionRole(bytes32, address, bytes4, uint8) external returns (bool) envfree;
    function canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
}

definition bitNot(uint256 input) returns uint256 = input xor max_uint256;

// Verify correct response from hasUserRole
rule hasUserRole(bytes32 ilk, address who, uint8 role) {
    bool ok = userRoles(ilk, who) & to_bytes32(assert_uint256(2^role)) != to_bytes32(0);

    bool ok2 = hasUserRole(ilk, who, role);

    assert ok2 == ok, "hasUserRole did not return the expected result";
}

// Verify correct response from hasActionRole
rule hasActionRole(bytes32 ilk, address target, bytes4 sign, uint8 role) {
    bool ok = actionsRoles(ilk, target, sign) & to_bytes32(assert_uint256(2^role)) != to_bytes32(0);

    bool ok2 = hasActionRole(ilk, target, sign, role);

    assert ok2 == ok, "hasActionRole did not return the expected result";
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;
    bytes32 anyBytes32;
    bytes4  anyBytes4;

    mathint wardsBefore = wards(anyAddr);
    address ilkAdminsBefore = ilkAdmins(anyBytes32);
    bytes32 userRolesBefore = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesBefore = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    address ilkAdminsAfter = ilkAdmins(anyBytes32);
    bytes32 userRolesAfter = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesAfter = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert ilkAdminsAfter != ilkAdminsBefore => f.selector == sig:setIlkAdmin(bytes32,address).selector, "ilkAdmins[x] changed in an unexpected function";
    assert userRolesAfter != userRolesBefore => f.selector == sig:setUserRole(bytes32,address,uint8,bool).selector, "userRoles[x][y] changed in an unexpected function";
    assert actionsRolesAfter != actionsRolesBefore => f.selector == sig:setRoleAction(bytes32,uint8,address,bytes4,bool).selector, "actionsRoles[x][y][z] changed in an unexpected function";
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

// Verify correct storage changes for non reverting setIlkAdmin
rule setIlkAdmin(bytes32 ilk, address usr) {
    env e;

    bytes32 otherBytes32;
    require otherBytes32 != ilk;

    address ilkAdminsOtherBefore = ilkAdmins(otherBytes32);

    setIlkAdmin(e, ilk, usr);

    address ilkAdminsIlkAfter = ilkAdmins(ilk);
    address ilkAdminsOtherAfter = ilkAdmins(otherBytes32);

    assert ilkAdminsIlkAfter == usr, "setIlkAdmin did not set ilkAdmins[ilk] to usr";
    assert ilkAdminsOtherAfter == ilkAdminsOtherBefore, "setIlkAdmin did not keep unchanged the rest of ilkAdmins[x]";
}

// Verify revert rules on setIlkAdmin
rule setIlkAdmin_revert(bytes32 ilk, address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setIlkAdmin@withrevert(e, ilk, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting setUserRole
rule setUserRole(bytes32 ilk, address who, uint8 role, bool enabled) {
    env e;

    bytes32 otherBytes32;
    address otherAddr;
    require otherBytes32 != ilk || otherAddr != who;

    bytes32 userRolesIlkWhoBefore = userRoles(ilk, who);
    bytes32 userRolesOtherBefore = userRoles(otherBytes32, otherAddr);
    uint256 mask = assert_uint256(2^role);
    bytes32 value = enabled ? userRolesIlkWhoBefore | to_bytes32(mask) : userRolesIlkWhoBefore & to_bytes32(bitNot(mask));

    setUserRole(e, ilk, who, role, enabled);

    bytes32 userRolesIlkWhoAfter = userRoles(ilk, who);
    bytes32 userRolesOtherAfter = userRoles(otherBytes32, otherAddr);

    assert userRolesIlkWhoAfter == value, "setUserRole did not set userRoles[ilk][who] by the corresponding value";
    assert userRolesOtherAfter == userRolesOtherBefore, "setUserRole did not keep unchanged the rest of userRoles[x][y]";
}

// Verify revert rules on setUserRole
rule setUserRole_revert(bytes32 ilk, address who, uint8 role, bool enabled) {
    env e;

    address ilkAuthIlk = ilkAdmins(ilk);

    setUserRole@withrevert(e, ilk, who, role, enabled);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ilkAuthIlk != e.msg.sender;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct storage changes for non reverting setRoleAction
rule setRoleAction(bytes32 ilk, uint8 role, address target, bytes4 sign, bool enabled) {
    env e;

    bytes32 otherBytes32;
    address otherAddr;
    bytes4  otherBytes4;
    require otherBytes32 != ilk || otherAddr != target || otherBytes4 != sign;

    bytes32 actionsRolesIlkTargetSigBefore = actionsRoles(ilk, target, sign);
    bytes32 actionsRolesOtherBefore = actionsRoles(otherBytes32, otherAddr, otherBytes4);
    uint256 mask = assert_uint256(2^role);
    bytes32 value = enabled ? actionsRolesIlkTargetSigBefore | to_bytes32(mask) : actionsRolesIlkTargetSigBefore & to_bytes32(bitNot(mask));

    setRoleAction(e, ilk, role, target, sign, enabled);

    bytes32 actionsRolesIlkTargetSigAfter = actionsRoles(ilk, target, sign);
    bytes32 actionsRolesOtherAfter = actionsRoles(otherBytes32, otherAddr, otherBytes4);

    assert actionsRolesIlkTargetSigAfter == value, "setRoleAction did not set actionsRoles[ilk][target][sig] by the corresponding value";
    assert actionsRolesOtherAfter == actionsRolesOtherBefore, "setRoleAction did not keep unchanged the rest of actionsRoles[x][y][z]";
}

// Verify revert rules on setRoleAction
rule setRoleAction_revert(bytes32 ilk, uint8 role, address target, bytes4 sign, bool enabled) {
    env e;

    address ilkAuthIlk = ilkAdmins(ilk);

    setRoleAction@withrevert(e, ilk, role, target, sign, enabled);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ilkAuthIlk != e.msg.sender;

    assert lastReverted <=> revert1 || revert2, "Revert rules failed";
}

// Verify correct response from canCall
rule canCall(bytes32 ilk, address caller, address target, bytes4 sign) {
    bool ok = userRoles(ilk, caller) & actionsRoles(ilk, target, sign) != to_bytes32(0);

    bool ok2 = canCall(ilk, caller, target, sign);

    assert ok2 == ok, "canCall did not return the expected result";
}
