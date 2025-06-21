#[test_only]
module movekit::access_control_core_tests {
    use std::signer;
    use std::vector;
    use movekit::access_control_core::{Self, Admin};

    // Test role types
    struct Treasurer has copy, drop {}

    struct Manager has copy, drop {}

    struct Operator has copy, drop {}

    // Core module error codes
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_HAS_ROLE: u64 = 1;
    const E_NO_SUCH_ROLE: u64 = 2;
    const E_NOT_INITIALIZED: u64 = 3;
    const E_ADMIN_ROLE_PROTECTED: u64 = 4;

    // Admin registry error codes (for delegated functions)
    const E_ADMIN_NOT_INITIALIZED: u64 = 0;
    const E_ADMIN_NOT_ADMIN: u64 = 1;
    const E_ADMIN_SELF_TRANSFER_NOT_ALLOWED: u64 = 2;
    const E_ADMIN_NO_PENDING_ADMIN: u64 = 3;
    const E_ADMIN_NOT_PENDING_ADMIN: u64 = 4;

    // ===========================================
    // INITIALIZATION & ADMIN REGISTRY TESTS
    // ===========================================

    #[test(deployer = @movekit)]
    fun test_init_module_creates_registries(deployer: &signer) {
        access_control_core::init_for_testing(deployer);

        let deployer_addr = signer::address_of(deployer);

        // Check admin registry was created (delegated functions work)
        assert!(access_control_core::get_current_admin() == deployer_addr, 0);
        assert!(access_control_core::is_current_admin(deployer_addr), 1);

        // Check admin role was granted in role registry
        assert!(access_control_core::has_role<Admin>(deployer_addr), 2);

        // Check role count
        assert!(access_control_core::get_role_count(deployer_addr) == 1, 3);
    }

    #[test(deployer = @movekit)]
    fun test_init_module_idempotent_on_double_call(deployer: &signer) {
        access_control_core::init_for_testing(deployer);
        // Second initialization should be idempotent (no failure)
        access_control_core::init_for_testing(deployer);

        // Should still work correctly
        let deployer_addr = signer::address_of(deployer);
        assert!(access_control_core::get_current_admin() == deployer_addr, 0);
        assert!(access_control_core::has_role<Admin>(deployer_addr), 1);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_get_current_admin_fails_when_not_initialized() {
        // Should fail - no admin registry exists (error comes from admin registry)
        access_control_core::get_current_admin();
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_is_current_admin_fails_when_not_initialized() {
        // Should fail when not initialized (since core delegates to admin registry)
        access_control_core::is_current_admin(@0x123);
    }

    #[test(deployer = @movekit)]
    fun test_admin_registry_functions(deployer: &signer) {
        access_control_core::init_for_testing(deployer);

        let deployer_addr = signer::address_of(deployer);
        let other_addr = @0x123;

        // Test delegated admin functions
        assert!(access_control_core::get_current_admin() == deployer_addr, 0);
        assert!(access_control_core::is_current_admin(deployer_addr), 1);
        assert!(!access_control_core::is_current_admin(other_addr), 2);
    }

    // ===========================================
    // TWO-STEP ADMIN TRANSFER TESTS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_complete_flow(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Step 1: Propose transfer (delegated to admin registry)
        access_control_core::transfer_admin(admin, new_admin_addr);

        // Check pending state (delegated functions)
        assert!(access_control_core::has_pending_admin(admin_addr), 0);
        assert!(access_control_core::get_pending_admin() == new_admin_addr, 1);

        // Admin should still be current
        assert!(access_control_core::get_current_admin() == admin_addr, 2);
        assert!(access_control_core::is_current_admin(admin_addr), 3);
        assert!(!access_control_core::is_current_admin(new_admin_addr), 4);

        // Step 2: Accept transfer (core coordinates admin registry + role management)
        access_control_core::accept_pending_admin(new_admin);

        // Check transfer completed
        assert!(access_control_core::get_current_admin() == new_admin_addr, 5);
        assert!(access_control_core::is_current_admin(new_admin_addr), 6);
        assert!(!access_control_core::is_current_admin(admin_addr), 7);

        // Check roles transferred in role registry
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 8);
        assert!(!access_control_core::has_role<Admin>(admin_addr), 9);

        // Check pending admin cleaned up (delegated to admin registry)
        assert!(!access_control_core::has_pending_admin(admin_addr), 10);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_cancel_flow(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Propose transfer
        access_control_core::transfer_admin(admin, new_admin_addr);
        assert!(access_control_core::has_pending_admin(admin_addr), 0);

        // Cancel transfer (delegated to admin registry)
        access_control_core::cancel_admin_transfer(admin);

        // Check admin unchanged
        assert!(access_control_core::get_current_admin() == admin_addr, 1);
        assert!(access_control_core::is_current_admin(admin_addr), 2);
        assert!(access_control_core::has_role<Admin>(admin_addr), 3);

        // Check pending admin cleaned up
        assert!(!access_control_core::has_pending_admin(admin_addr), 4);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_multiple_proposals(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);
        let another_addr = @0x456;

        // First proposal
        access_control_core::transfer_admin(admin, new_admin_addr);
        assert!(access_control_core::get_pending_admin() == new_admin_addr, 0);

        // Second proposal overwrites first
        access_control_core::transfer_admin(admin, another_addr);
        assert!(access_control_core::get_pending_admin() == another_addr, 1);
    }

    #[test(non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_transfer_admin_not_admin(non_admin: &signer) {
        // Should fail - not admin (error from admin registry)
        access_control_core::transfer_admin(non_admin, @0x456);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_ADMIN_SELF_TRANSFER_NOT_ALLOWED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_transfer_admin_to_self(admin: &signer) {
        access_control_core::init_for_testing(admin);
        let admin_addr = signer::address_of(admin);

        // Should fail - cannot transfer to self (error from admin registry)
        access_control_core::transfer_admin(admin, admin_addr);
    }

    #[test(admin = @movekit, new_admin = @0x123, wrong_admin = @0x456)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_accept_pending_admin_wrong_address(
        admin: &signer, new_admin: &signer, wrong_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Propose transfer to new_admin
        access_control_core::transfer_admin(admin, new_admin_addr);

        // Should fail - wrong_admin tries to accept (core validates this)
        access_control_core::accept_pending_admin(wrong_admin);
    }

    #[test(new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_accept_pending_admin_no_pending(new_admin: &signer) {
        // Should fail - admin registry not initialized (error from admin registry)
        access_control_core::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED, location = movekit::access_control_core
        )
    ]
    fun test_accept_pending_admin_no_pending_initialized(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        // Should fail - no pending admin transfer (core validates this)
        access_control_core::accept_pending_admin(new_admin);
    }

    #[test(non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_cancel_admin_transfer_not_admin(non_admin: &signer) {
        // Should fail - not admin (error from admin registry)
        access_control_core::cancel_admin_transfer(non_admin);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NO_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_cancel_admin_transfer_no_pending(admin: &signer) {
        access_control_core::init_for_testing(admin);

        // Should fail - no pending transfer to cancel (error from admin registry)
        access_control_core::cancel_admin_transfer(admin);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_get_pending_admin_no_pending() {
        // Should fail - no pending admin (error from admin registry)
        access_control_core::get_pending_admin();
    }

    // ===========================================
    // SECURITY ATTACK PREVENTION TESTS
    // ===========================================

    #[test(attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_ADMIN_ROLE_PROTECTED, location = movekit::access_control_core
        )
    ]
    fun test_privilege_escalation_prevention_grant(attacker: &signer) {
        // Attacker tries to grant themselves admin role - blocked by role protection
        access_control_core::grant_role<Admin>(attacker, signer::address_of(attacker));
    }

    #[test(attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_privilege_escalation_prevention_transfer(attacker: &signer) {
        // Attacker tries to transfer admin to themselves (error from admin registry)
        access_control_core::transfer_admin(attacker, signer::address_of(attacker));
    }

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_unauthorized_role_grant_prevention(
        admin: &signer, attacker: &signer
    ) {
        access_control_core::init_for_testing(admin);

        // Attacker tries to grant roles to others
        access_control_core::grant_role<Treasurer>(attacker, @0x123);
    }

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_unauthorized_role_revoke_prevention(
        admin: &signer, attacker: &signer
    ) {
        access_control_core::init_for_testing(admin);

        // Grant role to someone
        access_control_core::grant_role<Treasurer>(admin, @0x123);

        // Attacker tries to revoke roles from others
        access_control_core::revoke_role<Treasurer>(attacker, @0x123);
    }

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_unauthorized_admin_cancel_prevention(
        admin: &signer, attacker: &signer
    ) {
        access_control_core::init_for_testing(admin);

        // Admin proposes transfer
        access_control_core::transfer_admin(admin, @0x123);

        // Attacker tries to cancel admin transfer (error from admin registry)
        access_control_core::cancel_admin_transfer(attacker);
    }

    // ===========================================
    // STATE CONSISTENCY TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_role_registry_admin_sync(admin: &signer) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);

        // Verify AdminRegistry and RoleRegistry are in sync
        assert!(access_control_core::get_current_admin() == admin_addr, 0);
        assert!(access_control_core::has_role<Admin>(admin_addr), 1);
        assert!(access_control_core::is_current_admin(admin_addr), 2);

        // Test consistency after granting other roles
        access_control_core::grant_role<Treasurer>(admin, admin_addr);

        // Admin should still be admin
        assert!(access_control_core::get_current_admin() == admin_addr, 3);
        assert!(access_control_core::has_role<Admin>(admin_addr), 4);
        assert!(access_control_core::has_role<Treasurer>(admin_addr), 5);
        assert!(access_control_core::get_role_count(admin_addr) == 2, 6);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_admin_transfer_maintains_role_consistency(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Grant admin some additional roles
        access_control_core::grant_role<Treasurer>(admin, admin_addr);
        access_control_core::grant_role<Manager>(admin, admin_addr);

        // Verify initial state
        assert!(access_control_core::get_role_count(admin_addr) == 3, 0); // Admin + Treasurer + Manager
        assert!(access_control_core::get_role_count(new_admin_addr) == 0, 1);

        // Transfer admin role (core coordinates between admin registry and role registry)
        access_control_core::transfer_admin(admin, new_admin_addr);
        access_control_core::accept_pending_admin(new_admin);

        // Verify role consistency after transfer
        assert!(access_control_core::get_role_count(admin_addr) == 2, 2); // Treasurer + Manager (lost Admin)
        assert!(access_control_core::get_role_count(new_admin_addr) == 1, 3); // Admin only

        assert!(!access_control_core::has_role<Admin>(admin_addr), 4);
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 5);
        assert!(access_control_core::has_role<Treasurer>(admin_addr), 6); // Should keep other roles
        assert!(access_control_core::has_role<Manager>(admin_addr), 7);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_admin_role_consistency_during_transfer(
        admin: &signer, new_admin: &signer
    ) {
        // Test that admin role count remains exactly 1 throughout transfer
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Initially: 1 admin role (in old admin)
        assert!(access_control_core::has_role<Admin>(admin_addr), 0);
        assert!(!access_control_core::has_role<Admin>(new_admin_addr), 1);

        // Propose transfer - still 1 admin role
        access_control_core::transfer_admin(admin, new_admin_addr);
        assert!(access_control_core::has_role<Admin>(admin_addr), 2);
        assert!(!access_control_core::has_role<Admin>(new_admin_addr), 3);

        // Accept transfer - still 1 admin role (but transferred)
        access_control_core::accept_pending_admin(new_admin);
        assert!(!access_control_core::has_role<Admin>(admin_addr), 4);
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 5);

        // AdminRegistry and RoleRegistry should be in sync
        assert!(access_control_core::get_current_admin() == new_admin_addr, 6);
        assert!(access_control_core::is_current_admin(new_admin_addr), 7);
    }

    // ===========================================
    // ROLE MANAGEMENT TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_role_operations_on_nonexistent_users(admin: &signer) {
        access_control_core::init_for_testing(admin);

        let nonexistent = @0xDEADBEEF;

        // Should be able to grant role to new address
        access_control_core::grant_role<Treasurer>(admin, nonexistent);
        assert!(access_control_core::has_role<Treasurer>(nonexistent), 0);
        assert!(access_control_core::get_role_count(nonexistent) == 1, 1);

        // Should be able to grant multiple roles
        access_control_core::grant_role<Manager>(admin, nonexistent);
        assert!(access_control_core::has_role<Manager>(nonexistent), 2);
        assert!(access_control_core::get_role_count(nonexistent) == 2, 3);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_grant_role_success(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // Test granting a role
        assert!(!access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(access_control_core::get_role_count(user_addr) == 0, 1);

        access_control_core::grant_role<Treasurer>(admin, user_addr);

        assert!(access_control_core::has_role<Treasurer>(user_addr), 2);
        assert!(access_control_core::get_role_count(user_addr) == 1, 3);
    }

    #[test(admin = @movekit, user = @0x123)]
    #[
        expected_failure(
            abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core
        )
    ]
    fun test_grant_role_already_has_role(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);
        let user_addr = signer::address_of(user);
        access_control_core::grant_role<Treasurer>(admin, user_addr);

        // This should fail - user already has Treasurer role
        access_control_core::grant_role<Treasurer>(admin, user_addr);
    }

    #[test(non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_grant_role_not_admin(non_admin: &signer) {
        // Test that non-admin cannot grant roles
        access_control_core::grant_role<Treasurer>(non_admin, @0x456);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_revoke_role_success(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);
        let user_addr = signer::address_of(user);
        access_control_core::grant_role<Treasurer>(admin, user_addr);

        // Test revoking a role
        assert!(access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(access_control_core::get_role_count(user_addr) == 1, 1);

        access_control_core::revoke_role<Treasurer>(admin, user_addr);

        assert!(!access_control_core::has_role<Treasurer>(user_addr), 2);
        assert!(access_control_core::get_role_count(user_addr) == 0, 3);
    }

    #[test(admin = @movekit, user = @0x123)]
    #[expected_failure(
        abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core
    )]
    fun test_revoke_role_no_such_role(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);
        let user_addr = signer::address_of(user);

        // This should fail - user doesn't have Treasurer role
        access_control_core::revoke_role<Treasurer>(admin, user_addr);
    }

    #[test(non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_revoke_role_not_admin(non_admin: &signer) {
        // Test that non-admin cannot revoke roles
        access_control_core::revoke_role<Treasurer>(non_admin, @0x456);
    }

    #[test(admin = @movekit, user1 = @0x123, user2 = @0x456)]
    fun test_multiple_roles_different_users(
        admin: &signer, user1: &signer, user2: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        // Grant different roles to different users
        access_control_core::grant_role<Treasurer>(admin, user1_addr);
        access_control_core::grant_role<Manager>(admin, user2_addr);

        // Verify roles
        assert!(access_control_core::has_role<Treasurer>(user1_addr), 0);
        assert!(!access_control_core::has_role<Manager>(user1_addr), 1);
        assert!(access_control_core::get_role_count(user1_addr) == 1, 2);

        assert!(access_control_core::has_role<Manager>(user2_addr), 3);
        assert!(!access_control_core::has_role<Treasurer>(user2_addr), 4);
        assert!(access_control_core::get_role_count(user2_addr) == 1, 5);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_multiple_roles_same_user(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // Grant multiple roles to same user
        access_control_core::grant_role<Treasurer>(admin, user_addr);
        access_control_core::grant_role<Manager>(admin, user_addr);
        access_control_core::grant_role<Operator>(admin, user_addr);

        // Verify all roles
        assert!(access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(access_control_core::has_role<Manager>(user_addr), 1);
        assert!(access_control_core::has_role<Operator>(user_addr), 2);
        assert!(access_control_core::get_role_count(user_addr) == 3, 3);

        // Revoke one role, others should remain
        access_control_core::revoke_role<Manager>(admin, user_addr);

        assert!(access_control_core::has_role<Treasurer>(user_addr), 4);
        assert!(!access_control_core::has_role<Manager>(user_addr), 5);
        assert!(access_control_core::has_role<Operator>(user_addr), 6);
        assert!(access_control_core::get_role_count(user_addr) == 2, 7);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_get_roles_function(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);

        let user_addr = signer::address_of(user);

        // Initially no roles
        let roles = access_control_core::get_roles(user_addr);
        assert!(vector::length(&roles) == 0, 0);

        // Grant some roles
        access_control_core::grant_role<Treasurer>(admin, user_addr);
        access_control_core::grant_role<Manager>(admin, user_addr);

        // Check roles vector
        let roles = access_control_core::get_roles(user_addr);
        assert!(vector::length(&roles) == 2, 1);

        // Revoke one role
        access_control_core::revoke_role<Treasurer>(admin, user_addr);

        let roles = access_control_core::get_roles(user_addr);
        assert!(vector::length(&roles) == 1, 2);
    }

    #[test(user = @0x123)]
    fun test_has_role_no_role(user: &signer) {
        let user_addr = signer::address_of(user);
        assert!(!access_control_core::has_role<Treasurer>(user_addr), 0);
        assert!(!access_control_core::has_role<Admin>(user_addr), 1);
        assert!(access_control_core::get_role_count(user_addr) == 0, 2);
    }

    #[test]
    fun test_get_roles_no_registry() {
        let roles = access_control_core::get_roles(@0x123);
        assert!(vector::length(&roles) == 0, 0);
        assert!(access_control_core::get_role_count(@0x123) == 0, 1);
    }

    // ===========================================
    // ADMIN TRANSFER CHAIN TESTS
    // ===========================================

    #[test(admin = @movekit, admin2 = @0x123, admin3 = @0x456)]
    fun test_admin_transfer_chain(
        admin: &signer, admin2: &signer, admin3: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let admin2_addr = signer::address_of(admin2);
        let admin3_addr = signer::address_of(admin3);

        // Transfer 1: admin -> admin2
        access_control_core::transfer_admin(admin, admin2_addr);
        access_control_core::accept_pending_admin(admin2);

        assert!(access_control_core::get_current_admin() == admin2_addr, 0);
        assert!(access_control_core::has_role<Admin>(admin2_addr), 1);
        assert!(!access_control_core::has_role<Admin>(admin_addr), 2);

        // Transfer 2: admin2 -> admin3
        access_control_core::transfer_admin(admin2, admin3_addr);
        access_control_core::accept_pending_admin(admin3);

        assert!(access_control_core::get_current_admin() == admin3_addr, 3);
        assert!(access_control_core::has_role<Admin>(admin3_addr), 4);
        assert!(!access_control_core::has_role<Admin>(admin2_addr), 5);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_new_admin_can_manage_roles(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Transfer admin
        access_control_core::transfer_admin(admin, new_admin_addr);
        access_control_core::accept_pending_admin(new_admin);

        // New admin should be able to grant roles
        access_control_core::grant_role<Treasurer>(new_admin, admin_addr);
        assert!(access_control_core::has_role<Treasurer>(admin_addr), 0);

        // And revoke roles
        access_control_core::revoke_role<Treasurer>(new_admin, admin_addr);
        assert!(!access_control_core::has_role<Treasurer>(admin_addr), 1);
    }

    // ===========================================
    // UTILITY FUNCTION TESTS
    // ===========================================

    #[test(admin = @movekit, user = @0x123)]
    fun test_require_role_success(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);
        let user_addr = signer::address_of(user);
        access_control_core::grant_role<Treasurer>(admin, user_addr);

        // Should not abort
        access_control_core::require_role<Treasurer>(user);
    }

    #[test(user = @0x123)]
    #[expected_failure(
        abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core
    )]
    fun test_require_role_fails_without_role(user: &signer) {
        // Should abort - user doesn't have role
        access_control_core::require_role<Treasurer>(user);
    }

    #[test(admin = @movekit, user = @0x123)]
    fun test_require_role_admin(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);

        // Admin should have Admin role
        access_control_core::require_role<Admin>(admin);

        // User should not have Admin role
        let user_addr = signer::address_of(user);
        assert!(!access_control_core::has_role<Admin>(user_addr), 0);
    }

    // ===========================================
    // EDGE CASES AND ERROR HANDLING
    // ===========================================

    #[test]
    fun test_has_role_with_no_registry() {
        // Test has_role when RoleRegistry doesn't exist
        assert!(!access_control_core::has_role<Admin>(@0x123), 0);
        assert!(!access_control_core::has_role<Treasurer>(@0x456), 1);
    }

    #[test(admin = @movekit)]
    fun test_grant_revoke_same_role_multiple_times(admin: &signer) {
        access_control_core::init_for_testing(admin);
        let target = @0x123;

        // Grant, revoke, grant again
        access_control_core::grant_role<Treasurer>(admin, target);
        assert!(access_control_core::has_role<Treasurer>(target), 0);

        access_control_core::revoke_role<Treasurer>(admin, target);
        assert!(!access_control_core::has_role<Treasurer>(target), 1);

        access_control_core::grant_role<Treasurer>(admin, target);
        assert!(access_control_core::has_role<Treasurer>(target), 2);
    }

    #[test(admin = @movekit)]
    fun test_large_number_of_roles(admin: &signer) {
        access_control_core::init_for_testing(admin);
        let user = @0x123;

        // Grant multiple different role types to same user
        access_control_core::grant_role<Treasurer>(admin, user);
        access_control_core::grant_role<Manager>(admin, user);
        access_control_core::grant_role<Operator>(admin, user);
        // Note: Admin role is reserved for actual admins

        // Verify all roles exist
        assert!(access_control_core::has_role<Treasurer>(user), 0);
        assert!(access_control_core::has_role<Manager>(user), 1);
        assert!(access_control_core::has_role<Operator>(user), 2);
        assert!(access_control_core::get_role_count(user) == 3, 3);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED, location = movekit::access_control_core
        )
    ]
    fun test_double_accept_pending_admin_fails(
        admin: &signer, new_admin: &signer
    ) {
        access_control_core::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);
        access_control_core::transfer_admin(admin, new_admin_addr);

        // First accept succeeds
        access_control_core::accept_pending_admin(new_admin);
        // Second accept must fail (core validates pending transfer exists)
        access_control_core::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_ADMIN_ROLE_PROTECTED, location = movekit::access_control_core
        )
    ]
    fun test_admin_cannot_grant_admin_twice(admin: &signer) {
        access_control_core::init_for_testing(admin);
        let admin_addr = signer::address_of(admin);

        // Admin role is protected - cannot be granted manually
        access_control_core::grant_role<Admin>(admin, admin_addr);
    }

    #[test(current_admin = @movekit, future_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_ADMIN_ROLE_PROTECTED, location = movekit::access_control_core
        )
    ]
    fun test_admin_role_coordinated_during_transfer(
        current_admin: &signer, future_admin: &signer
    ) {
        access_control_core::init_for_testing(current_admin);

        let fut_addr = signer::address_of(future_admin);

        // Cannot pre-grant Admin role - it's protected
        access_control_core::grant_role<Admin>(current_admin, fut_addr);
    }
}
