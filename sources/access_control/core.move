module movekit::access_control_core {

    // -- Std & Framework Helpers -- //

    use std::signer;
    use std::event;
    use std::type_info::{Self, TypeInfo};
    use aptos_std::table::{Self, Table};
    use std::vector;

    // -- Types Section -- //

    /// Global role registry - stores all roles for all addresses
    struct RoleRegistry has key {
        roles: Table<address, vector<TypeInfo>> // address -> list of role types they have
    }

    /// Global admin registry - stores current admin address
    struct AdminRegistry has key {
        current_admin: address
    }

    /// Stores pending admin transfer
    struct PendingAdmin has key, drop {
        pending_admin: address
    }

    /// Built-in admin tag
    struct Admin has copy, drop {}

    // -- Constants Section -- //

    /// Error codes
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_HAS_ROLE: u64 = 1;
    const E_NO_SUCH_ROLE: u64 = 2;
    const E_NO_PENDING_ADMIN: u64 = 3;
    const E_NOT_PENDING_ADMIN: u64 = 4;
    const E_NOT_INITIALIZED: u64 = 5;
    const E_SELF_TRANSFER_NOT_ALLOWED: u64 = 6;

    // -- Events Section -- //

    #[event]
    struct RoleGrantedEvent<phantom T> has copy, drop, store {
        admin: address,
        target: address
    }

    #[event]
    struct RoleRevokedEvent<phantom T> has copy, drop, store {
        admin: address,
        target: address
    }

    #[event]
    struct AdminTransferProposed has copy, drop, store {
        current_admin: address,
        pending_admin: address
    }

    #[event]
    struct AdminTransferCompleted has copy, drop, store {
        old_admin: address,
        new_admin: address
    }

    #[event]
    struct AdminTransferCanceled has copy, drop, store {
        admin: address,
        canceled_pending: address
    }

    // -- External Functions Section -- //

    #[view]
    /// Get current admin address
    public fun get_current_admin(): address acquires AdminRegistry {
        assert!(exists<AdminRegistry>(@movekit), E_NOT_INITIALIZED);
        borrow_global<AdminRegistry>(@movekit).current_admin
    }

    #[view]
    /// Check if address is current admin
    public fun is_current_admin(addr: address): bool acquires AdminRegistry {
        if (!exists<AdminRegistry>(@movekit)) return false;
        let registry = borrow_global<AdminRegistry>(@movekit);
        registry.current_admin == addr
    }

    // -- Admin Transfer Functions --

    /// Current admin proposes new admin
    public fun transfer_admin(admin: &signer, new_admin: address) acquires AdminRegistry, PendingAdmin {
        let admin_addr = signer::address_of(admin);
        assert!(is_current_admin(admin_addr), E_NOT_ADMIN);
        assert!(new_admin != admin_addr, E_SELF_TRANSFER_NOT_ALLOWED);

        // Set or update pending admin
        if (exists<PendingAdmin>(admin_addr)) {
            let pending = borrow_global_mut<PendingAdmin>(admin_addr);
            pending.pending_admin = new_admin;
        } else {
            move_to(admin, PendingAdmin { pending_admin: new_admin });
        };

        event::emit(
            AdminTransferProposed { current_admin: admin_addr, pending_admin: new_admin }
        );
    }

    /// New admin accepts the transfer
    public fun accept_pending_admin(
        new_admin: &signer
    ) acquires PendingAdmin, AdminRegistry, RoleRegistry {
        let new_admin_addr = signer::address_of(new_admin);
        let current_admin = get_current_admin();

        assert!(exists<PendingAdmin>(current_admin), E_NO_PENDING_ADMIN);
        let pending = borrow_global<PendingAdmin>(current_admin);
        assert!(pending.pending_admin == new_admin_addr, E_NOT_PENDING_ADMIN);

        // Transfer the admin role in registry
        grant_role_internal<Admin>(new_admin_addr);
        // Grant first then revoke
        revoke_role_internal<Admin>(current_admin);

        // Update admin registry
        let registry = borrow_global_mut<AdminRegistry>(@movekit);
        registry.current_admin = new_admin_addr;

        // Clean up pending admin
        move_from<PendingAdmin>(current_admin);

        event::emit(
            AdminTransferCompleted { old_admin: current_admin, new_admin: new_admin_addr }
        );
    }

    /// Cancel pending admin transfer
    public fun cancel_admin_transfer(admin: &signer) acquires AdminRegistry, PendingAdmin {
        let admin_addr = signer::address_of(admin);
        assert!(is_current_admin(admin_addr), E_NOT_ADMIN);
        assert!(exists<PendingAdmin>(admin_addr), E_NO_PENDING_ADMIN);

        let pending = move_from<PendingAdmin>(admin_addr);

        event::emit(
            AdminTransferCanceled {
                admin: admin_addr,
                canceled_pending: pending.pending_admin
            }
        );
    }

    #[view]
    /// Get pending admin address
    public fun get_pending_admin(admin: address): address acquires PendingAdmin {
        assert!(exists<PendingAdmin>(admin), E_NO_PENDING_ADMIN);
        borrow_global<PendingAdmin>(admin).pending_admin
    }

    #[view]
    /// Check if there's a pending admin transfer
    public fun has_pending_admin(admin: address): bool {
        exists<PendingAdmin>(admin)
    }

    /// Admin grants role immediately
    public fun grant_role<T>(admin: &signer, target: address) acquires AdminRegistry, RoleRegistry {
        assert!(is_current_admin(signer::address_of(admin)), E_NOT_ADMIN);
        assert!(!has_role<T>(target), E_ALREADY_HAS_ROLE);

        grant_role_internal<T>(target);

        event::emit(
            RoleGrantedEvent<T> { admin: signer::address_of(admin), target: target }
        );
    }

    /// Admin revokes role immediately (standard practice)
    public fun revoke_role<T>(admin: &signer, target: address) acquires AdminRegistry, RoleRegistry {
        assert!(is_current_admin(signer::address_of(admin)), E_NOT_ADMIN);
        assert!(has_role<T>(target), E_NO_SUCH_ROLE);

        revoke_role_internal<T>(target);

        event::emit(
            RoleRevokedEvent<T> { admin: signer::address_of(admin), target: target }
        );
    }

    // -- View Functions --

    #[view]
    /// Check if address has specific role
    public fun has_role<T>(addr: address): bool acquires RoleRegistry {
        if (!exists<RoleRegistry>(@movekit)) return false;

        let registry = borrow_global<RoleRegistry>(@movekit);
        if (!table::contains(&registry.roles, addr))
            return false;

        let user_roles = table::borrow(&registry.roles, addr);
        let target_type = type_info::type_of<T>();

        vector_contains(user_roles, &target_type)
    }

    #[view]
    /// Get all roles for an address
    public fun get_roles(addr: address): vector<TypeInfo> acquires RoleRegistry {
        if (!exists<RoleRegistry>(@movekit)) return vector::empty();

        let registry = borrow_global<RoleRegistry>(@movekit);
        if (!table::contains(&registry.roles, addr))
            return vector::empty();

        *table::borrow(&registry.roles, addr)
    }

    #[view]
    /// Count total roles for an address
    public fun get_role_count(addr: address): u64 acquires RoleRegistry {
        vector::length(&get_roles(addr))
    }

    /// Utility function - assert account has role or abort
    public fun require_role<T>(account: &signer) acquires RoleRegistry {
        assert!(
            has_role<T>(signer::address_of(account)),
            E_NO_SUCH_ROLE
        );
    }

    // -- Internal Functions --

    /// Internal function to grant role using global registry
    fun grant_role_internal<T>(target: address) acquires RoleRegistry {
        let registry = borrow_global_mut<RoleRegistry>(@movekit);
        let role_type = type_info::type_of<T>();

        if (!table::contains(&registry.roles, target)) {
            table::add(&mut registry.roles, target, vector::empty<TypeInfo>());
        };

        let user_roles = table::borrow_mut(&mut registry.roles, target);

        if (!vector_contains(user_roles, &role_type)) {
            vector::push_back(user_roles, role_type);
        }
    }

    /// Internal function to revoke role using global registry
    fun revoke_role_internal<T>(target: address) acquires RoleRegistry {
        let registry = borrow_global_mut<RoleRegistry>(@movekit);
        let role_type = type_info::type_of<T>();

        let user_roles = table::borrow_mut(&mut registry.roles, target);
        let (found, index) = vector_find(user_roles, &role_type);
        assert!(found, E_NO_SUCH_ROLE);

        vector::remove(user_roles, index);

        if (vector::is_empty(user_roles)) {
            table::remove(&mut registry.roles, target);
        }
    }

    /// Helper function to check if vector contains element
    fun vector_contains(vec: &vector<TypeInfo>, item: &TypeInfo): bool {
        let (found, _) = vector_find(vec, item);
        found
    }

    /// Helper function to find element in vector
    fun vector_find(vec: &vector<TypeInfo>, item: &TypeInfo): (bool, u64) {
        let len = vector::length(vec);
        let i = 0;
        while (i < len) {
            if (vector::borrow(vec, i) == item) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    /// Bootstrap: give the deployer the Admin role and create registries
    fun init_module(admin: &signer) acquires RoleRegistry {
        let admin_addr = signer::address_of(admin);

        // Create admin registry
        move_to(admin, AdminRegistry { current_admin: admin_addr });

        // Create global role registry
        move_to(
            admin,
            RoleRegistry {
                roles: table::new<address, vector<TypeInfo>>()
            }
        );

        // Grant Admin role to deployer
        grant_role_internal<Admin>(admin_addr);

        event::emit(RoleGrantedEvent<Admin> { admin: admin_addr, target: admin_addr });
    }

    // Public init function for testing only
    #[test_only]
    public fun init_for_testing(admin: &signer) acquires RoleRegistry {
        init_module(admin);
    }
}
