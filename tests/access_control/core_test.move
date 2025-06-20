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
    const E_NO_PENDING_ADMIN: u64 = 3;
    const E_NOT_PENDING_ADMIN: u64 = 4;
    const E_NOT_INITIALIZED: u64 = 5;
    const E_SELF_TRANSFER_NOT_ALLOWED: u64 = 6;

    // ===========================================
    // INITIALIZATION & ADMIN REGISTRY TESTS
    // ===========================================

    #[test(deployer = @movekit)]
    fun test_init_module_creates_admin_registry(deployer: &signer) {
        access_control_core::init_for_testing(deployer);
        
        let deployer_addr = signer::address_of(deployer);
        
        // Check admin registry was created
        assert!(access_control_core::get_current_admin() == deployer_addr, 0);
        assert!(access_control_core::is_current_admin(deployer_addr), 1);
        
        // Check admin role was granted
        assert!(access_control_core::has_role<Admin>(deployer_addr), 2);
    }

    #[test(deployer = @movekit)]
    #[expected_failure]
    fun test_init_module_fails_if_already_initialized(deployer: &signer) {
        access_control_core::init_for_testing(deployer);
        // This should fail with RESOURCE_ALREADY_EXISTS when trying to move_to AdminRegistry again
        access_control_core::init_for_testing(deployer);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_INITIALIZED, location = movekit::access_control_core)]
    fun test_get_current_admin_fails_when_not_initialized() {
        // Should fail - no admin registry exists
        access_control_core::get_current_admin();
    }

    #[test]
    fun test_is_current_admin_returns_false_when_not_initialized() {
        // Should return false gracefully when not initialized
        assert!(!access_control_core::is_current_admin(@0x123), 0);
    }

    #[test(deployer = @movekit)]
    fun test_admin_registry_functions(deployer: &signer) {
        access_control_core::init_for_testing(deployer);
        
        let deployer_addr = signer::address_of(deployer);
        let other_addr = @0x123;
        
        // Test get_current_admin
        assert!(access_control_core::get_current_admin() == deployer_addr, 0);
        
        // Test is_current_admin
        assert!(access_control_core::is_current_admin(deployer_addr), 1);
        assert!(!access_control_core::is_current_admin(other_addr), 2);
    }

    // ===========================================
    // TWO-STEP ADMIN TRANSFER TESTS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_complete_flow(admin: &signer, new_admin: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        
        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);
        
        // Step 1: Propose transfer
        access_control_core::transfer_admin(admin, new_admin_addr);
        
        // Check pending state
        assert!(access_control_core::has_pending_admin(admin_addr), 0);
        assert!(access_control_core::get_pending_admin(admin_addr) == new_admin_addr, 1);
        
        // Admin should still be current
        assert!(access_control_core::get_current_admin() == admin_addr, 2);
        assert!(access_control_core::is_current_admin(admin_addr), 3);
        assert!(!access_control_core::is_current_admin(new_admin_addr), 4);
        
        // Step 2: Accept transfer
        access_control_core::accept_pending_admin(new_admin);
        
        // Check transfer completed
        assert!(access_control_core::get_current_admin() == new_admin_addr, 5);
        assert!(access_control_core::is_current_admin(new_admin_addr), 6);
        assert!(!access_control_core::is_current_admin(admin_addr), 7);
        
        // Check roles transferred
        assert!(access_control_core::has_role<Admin>(new_admin_addr), 8);
        assert!(!access_control_core::has_role<Admin>(admin_addr), 9);
        
        // Check pending admin cleaned up
        assert!(!access_control_core::has_pending_admin(admin_addr), 10);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_cancel_flow(admin: &signer, new_admin: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        
        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);
        
        // Propose transfer
        access_control_core::transfer_admin(admin, new_admin_addr);
        assert!(access_control_core::has_pending_admin(admin_addr), 0);
        
        // Cancel transfer
        access_control_core::cancel_admin_transfer(admin);
        
        // Check admin unchanged
        assert!(access_control_core::get_current_admin() == admin_addr, 1);
        assert!(access_control_core::is_current_admin(admin_addr), 2);
        assert!(access_control_core::has_role<Admin>(admin_addr), 3);
        
        // Check pending admin cleaned up
        assert!(!access_control_core::has_pending_admin(admin_addr), 4);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_multiple_proposals(admin: &signer, new_admin: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        
        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);
        let another_addr = @0x456;
        
        // First proposal
        access_control_core::transfer_admin(admin, new_admin_addr);
        assert!(access_control_core::get_pending_admin(admin_addr) == new_admin_addr, 0);
        
        // Second proposal overwrites first
        access_control_core::transfer_admin(admin, another_addr);
        assert!(access_control_core::get_pending_admin(admin_addr) == another_addr, 1);
    }

    #[test(non_admin = @0x123)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_transfer_admin_not_admin(non_admin: &signer) {
        // Should fail - not admin
        access_control_core::transfer_admin(non_admin, @0x456);
    }

    #[test(admin = @movekit)]
    #[expected_failure(abort_code = E_SELF_TRANSFER_NOT_ALLOWED, location = movekit::access_control_core)]
    fun test_transfer_admin_to_self(admin: &signer) {
        access_control_core::init_for_testing(admin);
        let admin_addr = signer::address_of(admin);
        
        // Should fail - cannot transfer to self
        access_control_core::transfer_admin(admin, admin_addr);
    }

    #[test(new_admin = @0x123)]
    #[expected_failure(abort_code = E_NOT_INITIALIZED, location = movekit::access_control_core)]
    fun test_accept_pending_admin_no_pending(new_admin: &signer) {
        // Should fail - admin registry not initialized (fails before checking pending admin)
        access_control_core::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[expected_failure(abort_code = E_NO_PENDING_ADMIN, location = movekit::access_control_core)]
    fun test_accept_pending_admin_no_pending_initialized(admin: &signer, new_admin: &signer) {
        // Setup admin but no pending transfer
        access_control_core::init_for_testing(admin);
        
        // Should fail - no pending admin transfer (but admin registry is initialized)
        access_control_core::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin = @0x123, wrong_admin = @0x456)]
    #[expected_failure(abort_code = E_NOT_PENDING_ADMIN, location = movekit::access_control_core)]
    fun test_accept_pending_admin_wrong_address(admin: &signer, new_admin: &signer, wrong_admin: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);
        
        // Propose transfer to new_admin
        access_control_core::transfer_admin(admin, new_admin_addr);
        
        // Should fail - wrong_admin tries to accept
        access_control_core::accept_pending_admin(wrong_admin);
    }

    #[test(non_admin = @0x123)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_cancel_admin_transfer_not_admin(non_admin: &signer) {
        // Should fail - not admin
        access_control_core::cancel_admin_transfer(non_admin);
    }

    #[test(admin = @movekit)]
    #[expected_failure(abort_code = E_NO_PENDING_ADMIN, location = movekit::access_control_core)]
    fun test_cancel_admin_transfer_no_pending(admin: &signer) {
        access_control_core::init_for_testing(admin);
        
        // Should fail - no pending transfer to cancel
        access_control_core::cancel_admin_transfer(admin);
    }

    #[test]
    #[expected_failure(abort_code = E_NO_PENDING_ADMIN, location = movekit::access_control_core)]
    fun test_get_pending_admin_no_pending() {
        // Should fail - no pending admin
        access_control_core::get_pending_admin(@0x123);
    }

    // ===========================================
    // ROLE MANAGEMENT TESTS (Updated for new admin pattern)
    // ===========================================

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
    #[expected_failure(abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core)]
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
    #[expected_failure(abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core)]
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
    fun test_transfer_role_success(admin: &signer, from_user: &signer, to_user: &signer) {
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
    #[expected_failure(abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core)]
    fun test_transfer_role_from_no_role(admin: &signer, from_user: &signer, to_user: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        
        // This should fail - from_user doesn't have Manager role
        access_control_core::transfer_role<Manager>(admin, from_user, to_user);
    }

    #[test(admin = @movekit, from_user = @0x123, to_user = @0x456)]
    #[expected_failure(abort_code = E_ALREADY_HAS_ROLE, location = movekit::access_control_core)]
    fun test_transfer_role_to_already_has_role(admin: &signer, from_user: &signer, to_user: &signer) {
        // Setup
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Manager>(admin, from_user);
        access_control_core::grant_role<Manager>(admin, to_user);
        
        // This should fail - to_user already has Manager role
        access_control_core::transfer_role<Manager>(admin, from_user, to_user);
    }

    #[test(non_admin = @0x123, from_user = @0x456, to_user = @0x789)]
    #[expected_failure(abort_code = E_NOT_ADMIN, location = movekit::access_control_core)]
    fun test_transfer_role_not_admin(non_admin: &signer, from_user: &signer, to_user: &signer) {
        // Test that non-admin cannot transfer roles
        access_control_core::transfer_role<Manager>(non_admin, from_user, to_user);
    }

    // ===========================================
    // ADMIN TRANSFER CHAIN TESTS
    // ===========================================

    #[test(admin = @movekit, admin2 = @0x123, admin3 = @0x456)]
    fun test_admin_transfer_chain(admin: &signer, admin2: &signer, admin3: &signer) {
        // Test transferring admin through a chain
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
    fun test_new_admin_can_manage_roles(admin: &signer, new_admin: &signer) {
        // Test that new admin can manage roles after transfer
        access_control_core::init_for_testing(admin);
        
        let new_admin_addr = signer::address_of(new_admin);
        
        // Transfer admin
        access_control_core::transfer_admin(admin, new_admin_addr);
        access_control_core::accept_pending_admin(new_admin);
        
        // New admin should be able to grant roles
        access_control_core::grant_role<Treasurer>(new_admin, admin);
        assert!(access_control_core::has_role<Treasurer>(signer::address_of(admin)), 0);
        
        // And revoke roles
        access_control_core::revoke_role<Treasurer>(new_admin, signer::address_of(admin));
        assert!(!access_control_core::has_role<Treasurer>(signer::address_of(admin)), 1);
    }

    // ===========================================
    // UTILITY FUNCTION TESTS
    // ===========================================

    #[test(admin = @movekit, user = @0x123)]
    fun test_require_role_success(admin: &signer, user: &signer) {
        access_control_core::init_for_testing(admin);
        access_control_core::grant_role<Treasurer>(admin, user);
        
        // Should not abort
        access_control_core::require_role<Treasurer>(user);
    }

    #[test(user = @0x123)]
    #[expected_failure(abort_code = E_NO_SUCH_ROLE, location = movekit::access_control_core)]
    fun test_require_role_fails_without_role(user: &signer) {
        // Should abort - user doesn't have role
        access_control_core::require_role<Treasurer>(user);
    }

    // ===========================================
    // COMPLEX SCENARIO TESTS
    // ===========================================

    #[test(admin = @movekit, user1 = @0x123, user2 = @0x456)]
    fun test_multiple_roles_different_users(admin: &signer, user1: &signer, user2: &signer) {
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
}