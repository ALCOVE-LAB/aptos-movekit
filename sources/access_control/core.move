module movekit::access_control_core {

    // -- Std & Framework Helpers -- //

    use std::signer;
    use std::event;

    // -- Types Section -- //

    /// Marker resource: "address *A* holds role *T*"
    struct Role<phantom T> has key, drop {}

    /// Global admin registry - stores current admin address
    /// TODO: Consider making this generic/per-module in future versions
    struct AdminRegistry has key {
        current_admin: address,
    }

    /// Stores pending admin transfer
    struct PendingAdmin has key, drop {
        pending_admin: address,
    }

    /// Built-in admin tag.  Other modules may define their own empty structs.
    struct Admin has copy, drop {}

    // -- Constants Section -- //

    /// Error codes
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_HAS_ROLE: u64 = 1;
    const E_NO_SUCH_ROLE: u64 = 2;
    const E_NO_PENDING_ADMIN: u64 = 3;
    const E_NOT_PENDING_ADMIN: u64 = 4;
    const E_NOT_INITIALIZED: u64 = 5;

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
    struct RoleTransferredEvent<phantom T> has copy, drop, store {
        admin: address,
        from: address,
        to: address
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

    /// Step 1: Current admin proposes new admin
    public fun transfer_admin(admin: &signer, new_admin: address) acquires AdminRegistry, PendingAdmin {
        let admin_addr = signer::address_of(admin);
        assert!(is_current_admin(admin_addr), E_NOT_ADMIN);
        assert!(new_admin != admin_addr, E_ALREADY_HAS_ROLE);
        
        // Set or update pending admin
        if (exists<PendingAdmin>(admin_addr)) {
            let pending = borrow_global_mut<PendingAdmin>(admin_addr);
            pending.pending_admin = new_admin;
        } else {
            move_to(admin, PendingAdmin { pending_admin: new_admin });
        };

        event::emit(AdminTransferProposed {
            current_admin: admin_addr,
            pending_admin: new_admin
        });
    }

    /// Step 2: New admin accepts the transfer
    public fun accept_pending_admin(new_admin: &signer) acquires Role, PendingAdmin, AdminRegistry {
        let new_admin_addr = signer::address_of(new_admin);
        let current_admin = get_current_admin();
        
        assert!(exists<PendingAdmin>(current_admin), E_NO_PENDING_ADMIN);
        let pending = borrow_global<PendingAdmin>(current_admin);
        assert!(pending.pending_admin == new_admin_addr, E_NOT_PENDING_ADMIN);
        
        // Transfer the admin role
        move_from<Role<Admin>>(current_admin);
        move_to<Role<Admin>>(new_admin, Role<Admin> {});
        
        // Update admin registry
        let registry = borrow_global_mut<AdminRegistry>(@movekit);
        registry.current_admin = new_admin_addr;
        
        // Clean up pending admin
        move_from<PendingAdmin>(current_admin);

        event::emit(AdminTransferCompleted {
            old_admin: current_admin,
            new_admin: new_admin_addr
        });
    }

    /// Cancel pending admin transfer
    public fun cancel_admin_transfer(admin: &signer) acquires AdminRegistry, PendingAdmin {
        let admin_addr = signer::address_of(admin);
        assert!(is_current_admin(admin_addr), E_NOT_ADMIN);
        assert!(exists<PendingAdmin>(admin_addr), E_NO_PENDING_ADMIN);
        
        let pending = move_from<PendingAdmin>(admin_addr);
        
        event::emit(AdminTransferCanceled {
            admin: admin_addr,
            canceled_pending: pending.pending_admin
        });
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

    /// Grants a role to an address
    public fun grant_role<T>(admin: &signer, target: &signer) acquires AdminRegistry {
        grant_role_internal<T>(admin, target);
    }

    /// Revokes a role from an address
    public fun revoke_role<T>(admin: &signer, target: address) acquires Role, AdminRegistry {
        revoke_role_internal<T>(admin, target);
    }

    /// Transfers a role from one address to another
    public fun transfer_role<T>(
        admin: &signer, from: &signer, to: &signer
    ) acquires Role, AdminRegistry {
        assert!(
            is_current_admin(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(
            exists<Role<T>>(signer::address_of(from)),
            E_NO_SUCH_ROLE
        );

        assert!(
            !exists<Role<T>>(signer::address_of(to)),
            E_ALREADY_HAS_ROLE
        );

        move_from<Role<T>>(signer::address_of(from));
        move_to<Role<T>>(to, Role<T> {});

        event::emit(
            RoleTransferredEvent<T> {
                admin: signer::address_of(admin),
                from: signer::address_of(from),
                to: signer::address_of(to)
            }
        );
    }

    // View helper to check whether an address currently holds role T
    #[view]
    public fun has_role<T>(addr: address): bool {
        exists<Role<T>>(addr)
    }

    /// Utility function - assert account has role or abort
    public fun require_role<T>(account: &signer) {
        assert!(has_role<T>(signer::address_of(account)), E_NO_SUCH_ROLE);
    }

    // -- Internal Functions Section -- //

    /// Bootstrap: give the deployer the Admin role and create admin registry
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        // Create admin registry first
        move_to(admin, AdminRegistry {
            current_admin: admin_addr,
        });
        
        // Grant Admin role to caller
        assert!(
            !exists<Role<Admin>>(admin_addr),
            E_ALREADY_HAS_ROLE
        );
        move_to<Role<Admin>>(admin, Role<Admin> {});

        event::emit(
            RoleGrantedEvent<Admin> {
                admin: admin_addr,
                target: admin_addr
            }
        );
    }

    /// Grants a role to an address
    fun grant_role_internal<T>(admin: &signer, target: &signer) acquires AdminRegistry {
        assert!(
            is_current_admin(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(
            !exists<Role<T>>(signer::address_of(target)),
            E_ALREADY_HAS_ROLE
        );
        move_to<Role<T>>(target, Role<T> {});

        event::emit(
            RoleGrantedEvent<T> {
                admin: signer::address_of(admin),
                target: signer::address_of(target)
            }
        );
    }

    /// Revokes a role from an address
    fun revoke_role_internal<T>(admin: &signer, target: address) acquires Role, AdminRegistry {
        assert!(
            is_current_admin(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(exists<Role<T>>(target), E_NO_SUCH_ROLE);
        move_from<Role<T>>(target);

        event::emit(
            RoleRevokedEvent<T> { admin: signer::address_of(admin), target: target }
        );
    }

    // Public init function for testing only
    #[test_only]
    public fun init_for_testing(admin: &signer) {
        init_module(admin);
    }
}
