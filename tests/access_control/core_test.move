#[test_only]
module movekit::access_control_core_tests {
    use std::signer;
    use movekit::access_control_core::{Self, Admin};

    // Test role types
    struct Treasurer has copy, drop {}

    struct Manager has copy, drop {}

    struct Operator has copy, drop {}

    // Test constants
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_HAS_ROLE: u64 = 1;
    const E_NO_SUCH_ROLE: u64 = 2;

    #[test(deployer = @movekit)]
    fun test_init_module_success(deployer: &signer) {
        // Test that init_module grants Admin role to deployer
        access_control_core::init_for_testing(deployer);

        let deployer_addr = signer::address_of(deployer);
        assert!(access_control_core::has_role<Admin>(deployer_addr), 0);
    }

    #[test(deployer = @movekit)]
    #[
        expected_failure(
            abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core
        )
    ]
    fun test_init_module_already_has_admin(deployer: &signer) {
        // Test that init_module fails if deployer already has Admin role
        access_control_core::init_for_testing(deployer);
        // This should fail
        access_control_core::init_for_testing(deployer);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_grant_role_success(admin: &signer, user: &signer) {
        // Setup: admin gets Admin role
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // Test granting a role
        assert!(!access_control_core::has_role<Treasurer>(user_addr), 0);
        access_control_core::grant_role<Treasurer>(admin, user);
        assert!(access_control_core::has_role<Treasurer>(user_addr), 1);
    }

    #[test(admin = @movekit, user = @0x123)]
    #[
        expected_failure(
            abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core
        )
    ]
    fun test_grant_role_already_has_role(admin: &signer, user: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Treasurer>(admin, user);

        // This should fail - user already has Treasurer role
        access_control_core::grant_role<Treasurer>(admin, user);
    }

    #[test(non_admin = @0x123, user = @0x456)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_grant_role_not_admin(non_admin: &signer, user: &signer) {
        // Test that non-admin cannot grant roles
        access_control_core::grant_role<Treasurer>(non_admin, user);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_revoke_role_success(admin: &signer, user: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Treasurer>(admin, user);

        let user_addr = signer::address_of(user);

        // Test revoking a role
        assert!(access_control_core::has_role<Treasurer>(user_addr), 0);
        access_control_core::revoke_role<Treasurer>(admin, user_addr);
        assert!(!access_control_core::has_role<Treasurer>(user_addr), 1);
    }

    #[test(admin = @movekit, user = @0x123)]
    #[expected_failure(
        abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core
    )]
    fun test_revoke_role_no_such_role(admin: &signer, user: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // This should fail - user doesn't have Treasurer role
        access_control_core::revoke_role<Treasurer>(admin, user_addr);
    }

    #[test(non_admin = @0x123, user = @0x456)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_revoke_role_not_admin(non_admin: &signer, user: &signer) {
        let user_addr = signer::address_of(user);

        // Test that non-admin cannot revoke roles
        access_control_core::revoke_role<Treasurer>(non_admin, user_addr);
    }

    #[test(admin = @movekit, from_user = @0x123, to_user = @0x456)]
    fun test_transfer_role_success(
        admin: &signer, from_user: &signer, to_user: &signer
    ) {
        // Setup
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Manager>(admin, from_user);

        let from_addr = signer::address_of(from_user);
        let to_addr = signer::address_of(to_user);

        // Test transferring a role
        assert!(access_control_core::has_role<Manager>(from_addr), 0);
        assert!(!access_control_core::has_role<Manager>(to_addr), 1);

        access_control_core::transfer_role<Manager>(admin, from_user, to_user);

        assert!(!access_control_core::has_role<Manager>(from_addr), 2);
        assert!(access_control_core::has_role<Manager>(to_addr), 3);
    }

    #[test(admin = @movekit, from_user = @0x123, to_user = @0x456)]
    #[expected_failure(
        abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core
    )]
    fun test_transfer_role_from_no_role(
        admin: &signer, from_user: &signer, to_user: &signer
    ) {
        // Setup
        access_control_core::init_for_testing(admin);

        // This should fail - from_user doesn't have Manager role
        access_control_core::transfer_role<Manager>(admin, from_user, to_user);
    }

    #[test(admin = @movekit, from_user = @0x123, to_user = @0x456)]
    #[
        expected_failure(
            abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core
        )
    ]
    fun test_transfer_role_to_already_has_role(
        admin: &signer, from_user: &signer, to_user: &signer
    ) {
        // Setup
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Manager>(admin, from_user);
        access_control_core::grant_role<Manager>(admin, to_user);

        // This should fail - to_user already has Manager role
        access_control_core::transfer_role<Manager>(admin, from_user, to_user);
    }

    #[test(non_admin = @0x123, from_user = @0x456, to_user = @0x789)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_transfer_role_not_admin(
        non_admin: &signer, from_user: &signer, to_user: &signer
    ) {
        // Test that non-admin cannot transfer roles
        access_control_core::transfer_role<Manager>(non_admin, from_user, to_user);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_success(admin: &signer, new_admin: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Test transferring admin role
        assert!(access_control_core::has_role<Admin>(admin_addr), 0);
        assert!(!access_control_core::has_role<Admin>(new_admin_addr), 1);

        access_control_core::transfer_admin(admin, new_admin);

        assert!(!access_control_core::has_role<Admin>(admin_addr), 2);
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 3);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core
        )
    ]
    fun test_transfer_admin_already_has_admin(
        admin: &signer, new_admin: &signer
    ) {
        // Setup - both have admin roles
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Admin>(admin, new_admin);

        // This should fail - new_admin already has Admin role
        access_control_core::transfer_admin(admin, new_admin);
    }

    #[test(non_admin = @0x123, new_admin = @0x456)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_transfer_admin_not_admin(
        non_admin: &signer, new_admin: &signer
    ) {
        // Test that non-admin cannot transfer admin role
        access_control_core::transfer_admin(non_admin, new_admin);
    }

    #[test(admin = @movekit, user1 = @0x123, user2 = @0x456)]
    fun test_multiple_roles_different_users(
        admin: &signer, user1: &signer, user2: &signer
    ) {
        // Test that different users can have different roles
        access_control_core::init_for_testing(admin);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        // Grant different roles to different users
        access_control_core::grant_role<Treasurer>(admin, user1);
        access_control_core::grant_role<Manager>(admin, user2);

        // Verify roles
        assert!(access_control_core::has_role<Treasurer>(user1_addr), 0);
        assert!(!access_control_core::has_role<Manager>(user1_addr), 1);

        assert!(access_control_core::has_role<Manager>(user2_addr), 2);
        assert!(!access_control_core::has_role<Treasurer>(user2_addr), 3);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_multiple_roles_same_user(admin: &signer, user: &signer) {
        // Test that same user can have multiple roles
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // Grant multiple roles to same user
        access_control_core::grant_role<Treasurer>(admin, user);
        access_control_core::grant_role<Manager>(admin, user);
        access_control_core::grant_role<Operator>(admin, user);

        // Verify all roles
        assert!(access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(access_control_core::has_role<Manager>(user_addr), 1);
        assert!(access_control_core::has_role<Operator>(user_addr), 2);

        // Revoke one role, others should remain
        access_control_core::revoke_role<Manager>(admin, user_addr);

        assert!(access_control_core::has_role<Treasurer>(user_addr), 3);
        assert!(!access_control_core::has_role<Manager>(user_addr), 4);
        assert!(access_control_core::has_role<Operator>(user_addr), 5);
    }

    #[test(user = @0x123)]
    fun test_has_role_no_role(user: &signer) {
        // Test has_role returns false for non-existent role
        let user_addr = signer::address_of(user);
        assert!(!access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(!access_control_core::has_role<Admin>(user_addr), 1);
    }

    #[test(admin = @movekit, old_admin = @0x123, new_admin = @0x456)]
    fun test_admin_transfer_chain(
        admin: &signer, old_admin: &signer, new_admin: &signer
    ) {
        // Test transferring admin through a chain
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let old_admin_addr = signer::address_of(old_admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Transfer admin from original to old_admin
        access_control_core::transfer_admin(admin, old_admin);
        assert!(!access_control_core::has_role<Admin>(admin_addr), 0);
        assert!(access_control_core::has_role<Admin>(old_admin_addr), 1);

        // Transfer admin from old_admin to new_admin
        access_control_core::transfer_admin(old_admin, new_admin);
        assert!(!access_control_core::has_role<Admin>(old_admin_addr), 2);
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 3);
    }
}
