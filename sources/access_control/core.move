module movekit::access_control_core {

    // -- Dependencies -- //

    use std::signer;
    use std::event;
    use std::type_info::{Self, TypeInfo};
    use aptos_std::table::{Self, Table};
    use aptos_std::ordered_map::{Self, OrderedMap};
    use std::vector;
    use movekit::access_control_admin_registry;

    // -- Core Types -- //

    /// Global role registry mapping addresses to role types
    struct RoleRegistry has key {
        /// Maps addresses to their assigned roles
        roles: Table<address, OrderedMap<TypeInfo, bool>>
    }

    /// Built-in Admin role type (managed via transfer only)
    struct Admin has copy, drop {}

    // -- Error Codes -- //

    /// Unauthorized access attempt - caller lacks required permissions
    const E_NOT_ADMIN: u64 = 0;
    /// Role already assigned to target address
    const E_ALREADY_HAS_ROLE: u64 = 1;
    /// Attempted to revoke non-existent role
    const E_NO_SUCH_ROLE: u64 = 2;
    /// Attempted operation on uninitialized system
    const E_NOT_INITIALIZED: u64 = 3;
    /// Admin role cannot be manually managed - use admin transfer instead
    const E_ADMIN_ROLE_PROTECTED: u64 = 4;
    /// State corruption detected between admin registry and role registry
    const E_STATE_CORRUPTION: u64 = 5;

    // -- Events -- //

    #[event]
    /// Emitted when a role is successfully granted to an address
    struct RoleGranted<phantom T> has copy, drop, store {
        /// Address of admin who granted the role
        admin: address,
        /// Address that received the role
        target: address,
        /// Type information of the granted role
        role: TypeInfo
    }

    #[event]
    /// Emitted when a role is successfully revoked from an address
    struct RoleRevoked<phantom T> has copy, drop, store {
        /// Address of admin who revoked the role
        admin: address,
        /// Address that lost the role
        target: address
    }

    #[event]
    /// Emitted when admin role is transferred to a new admin
    struct AdminRoleTransferred has copy, drop, store {
        /// Previous admin who lost Admin role
        old_admin: address,
        /// New admin who gained Admin role
        new_admin: address
    }

    // -- Package Functions -- //

    /// Propose admin transfer - delegates to admin registry
    package fun transfer_admin(admin: &signer, new_admin: address) {
        access_control_admin_registry::transfer_admin(admin, new_admin)
    }

    /// Accept pending admin transfer and synchronize role assignments
    package fun accept_pending_admin(new_admin: &signer) acquires RoleRegistry {
        let new_admin_addr = signer::address_of(new_admin);

        // Capture current state before any modifications
        let current_admin_addr = access_control_admin_registry::get_current_admin();

        // Validate pending transfer exists and matches caller
        assert!(
            access_control_admin_registry::has_pending_admin(),
            E_NOT_INITIALIZED
        );
        assert!(
            access_control_admin_registry::get_pending_admin() == new_admin_addr,
            E_NOT_ADMIN
        );

        // Execute admin transfer atomically
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Synchronize Admin role assignments to maintain consistency
        synchronize_admin_role(current_admin_addr, new_admin_addr);

        // Emit synchronization event for audit trail
        event::emit(
            AdminRoleTransferred {
                old_admin: current_admin_addr,
                new_admin: new_admin_addr
            }
        );
    }

    /// Cancel pending admin transfer - delegates to admin registry
    package fun cancel_admin_transfer(admin: &signer) {
        access_control_admin_registry::cancel_admin_transfer(admin)
    }

    // -- Role Management Functions -- //

    /// Grant role to target address (Admin role; admin-only)
    public fun grant_role<T>(admin: &signer, target: address) acquires RoleRegistry {
        // Security: Prevent manual Admin role manipulation
        assert_not_admin_role<T>();

        // Authorize admin access
        require_admin(admin);

        // Validate role assignment
        assert!(!has_role<T>(target), E_ALREADY_HAS_ROLE);

        // Execute role grant
        grant_role_internal<T>(target);

        // Emit audit event
        event::emit(
            RoleGranted<T> {
                admin: signer::address_of(admin),
                target: target,
                role: type_info::type_of<T>()
            }
        );
    }

    /// Revoke role from target address (Admin role; admin-only)
    package fun revoke_role<T>(admin: &signer, target: address) acquires RoleRegistry {
        // Security: Prevent manual Admin role manipulation
        assert_not_admin_role<T>();

        // Authorize admin access
        require_admin(admin);

        // Validate role exists
        assert!(has_role<T>(target), E_NO_SUCH_ROLE);

        // Execute role revocation
        revoke_role_internal<T>(target);

        // Emit audit event
        event::emit(
            RoleRevoked<T> { admin: signer::address_of(admin), target: target }
        );
    }

    // -- Public functions -- //

    /// Assert caller has required role or abort with clear error
    /// Useful for other modules requiring specific role authorization
    public fun require_role<T>(account: &signer) acquires RoleRegistry {
        assert!(
            has_role<T>(signer::address_of(account)),
            E_NO_SUCH_ROLE
        );
    }

    // -- View Functions -- //

    #[view]
    /// Check if address has a specific role
    /// Returns false if the registry or user entry does not exist
    public fun has_role<T>(addr: address): bool acquires RoleRegistry {
        // Handle uninitialized system gracefully
        if (!exists<RoleRegistry>(@movekit)) return false;

        let registry = &RoleRegistry[@movekit];

        // Handle non-existent user gracefully
        if (!registry.roles.contains(addr)) return false;

        let user_roles = registry.roles.borrow(addr);
        let target_type = type_info::type_of<T>();

        user_roles.contains(&target_type)
    }

    #[view]
    /// Get current admin address from admin registry
    public fun get_current_admin(): address {
        access_control_admin_registry::get_current_admin()
    }

    #[view]
    /// Check if given address is the current admin
    public fun is_current_admin(addr: address): bool {
        access_control_admin_registry::is_current_admin(addr)
    }

    #[view]
    /// Get all roles assigned to an address in sorted order
    /// Returns empty vector for uninitialized system or non-existent users
    public fun get_roles(addr: address): vector<TypeInfo> acquires RoleRegistry {
        // Handle uninitialized system gracefully
        if (!exists<RoleRegistry>(@movekit)) return vector::empty();

        let registry = &RoleRegistry[@movekit];

        // Handle non-existent user gracefully
        if (!registry.roles.contains(addr)) return vector::empty();

        let user_roles = registry.roles.borrow(addr);

        // Extract keys from OrderedMap (automatically sorted)
        ordered_map::keys(user_roles)
    }

    #[view]
    /// Count total roles assigned to an address
    public fun get_role_count(addr: address): u64 acquires RoleRegistry {
        // Handle uninitialized system gracefully
        if (!exists<RoleRegistry>(@movekit)) return 0;

        let registry = &RoleRegistry[@movekit];

        // Handle non-existent user gracefully
        if (!registry.roles.contains(addr)) return 0;

        let user_roles = registry.roles.borrow(addr);

        ordered_map::length(user_roles)
    }

    #[view]
    /// Get pending admin address from admin registry
    public fun get_pending_admin(): address {
        access_control_admin_registry::get_pending_admin()
    }

    #[view]
    /// Check if admin has pending transfer
    public fun has_pending_admin(): bool {
        access_control_admin_registry::has_pending_admin()
    }

    // -- Internal Implementation -- //

    /// Synchronize Admin role during admin transfer
    /// Ensures exactly one Admin role exists and belongs to current admin
    fun synchronize_admin_role(old_admin: address, new_admin: address) acquires RoleRegistry {
        // Validate registry is initialized
        assert!(exists<RoleRegistry>(@movekit), E_NOT_INITIALIZED);

        // Grant Admin role to new admin (safe - handles duplicates)
        grant_role_internal<Admin>(new_admin);

        // Revoke Admin role from old admin (safe - handles non-existence)
        revoke_role_internal<Admin>(old_admin);

        // Verify state consistency after synchronization
        assert!(has_role<Admin>(new_admin), E_STATE_CORRUPTION);
        assert!(!has_role<Admin>(old_admin), E_STATE_CORRUPTION);
    }

    /// Internal role granting with duplicate protection
    fun grant_role_internal<T>(target: address) acquires RoleRegistry {
        let registry = &mut RoleRegistry[@movekit];
        let role_type = type_info::type_of<T>();

        // Initialize user's role map if needed
        if (!registry.roles.contains(target)) {
            registry.roles.add(target, ordered_map::new<TypeInfo, bool>());
        };

        let user_roles = registry.roles.borrow_mut(target);

        // Only add role if not already present (idempotent operation)
        if (!user_roles.contains(&role_type)) {
            user_roles.add(role_type, true);
        }
    }

    /// Internal role revocation with non-existence protection
    fun revoke_role_internal<T>(target: address) acquires RoleRegistry {
        let registry = &mut RoleRegistry[@movekit];
        let role_type = type_info::type_of<T>();

        // Handle non-existent user gracefully
        if (!registry.roles.contains(target)) return;

        let user_roles = registry.roles.borrow_mut(target);

        // Only remove if role exists (idempotent operation)
        if (user_roles.contains(&role_type)) {
            user_roles.remove(&role_type);

            // Clean up empty role maps to save storage
            if (ordered_map::is_empty(user_roles)) {
                let empty_map = registry.roles.remove(target);
                ordered_map::destroy_empty(empty_map);
            }
        }
    }

    /// Require admin authorization with clear error messaging
    fun require_admin(admin: &signer) {
        access_control_admin_registry::require_admin(admin);
    }

    /// Security check: prevent manual Admin role manipulation
    fun assert_not_admin_role<T>() {
        assert!(
            type_info::type_of<T>() != type_info::type_of<Admin>(),
            E_ADMIN_ROLE_PROTECTED
        );
    }

    /// System initialization - creates role registry and grants initial Admin role
    fun init_module(admin: &signer) acquires RoleRegistry {
        let admin_addr = signer::address_of(admin);

        // Initialize admin registry first (idempotent operation)
        access_control_admin_registry::init_admin_registry(admin);

        // Create role registry if not already exists
        if (!exists<RoleRegistry>(@movekit)) {
            move_to(
                admin,
                RoleRegistry {
                    roles: table::new<address, OrderedMap<TypeInfo, bool>>()
                }
            );
        };

        // Grant initial Admin role to deployer
        grant_role_internal<Admin>(admin_addr);

        // Emit initial role grant event
        event::emit(
            RoleGranted<Admin> {
                admin: admin_addr,
                target: admin_addr,
                role: type_info::type_of<Admin>()
            }
        );
    }

    // -- Testing Support -- //

    #[test_only]
    /// Initialize system for testing purposes
    package fun init_for_testing(admin: &signer) acquires RoleRegistry {
        init_module(admin);
    }
}
