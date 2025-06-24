# Access Control System

Role-based access control (RBAC) for Aptos Move contracts using phantom types.

## Architecture

Two modules:
- `access_control_admin_registry` - Manages admin transfers with two-step verification
- `access_control_core` - Handles role assignments and authorization

## Usage

### Define Roles
```move
struct Treasurer has copy, drop {}
struct Manager has copy, drop {}
```

### Protect Functions
```move
public entry fun withdraw(account: &signer, amount: u64) {
    access_control_core::require_role<Treasurer>(account);
    // protected logic
}
```

### Manage Roles (Admin Only)
```move
// Grant role
access_control_core::grant_role<Treasurer>(admin, user_address);

// Revoke role
access_control_core::revoke_role<Treasurer>(admin, user_address);

// Check role
let has_role = access_control_core::has_role<Treasurer>(user_address);
```

### Transfer Admin
```move
// Step 1: Current admin proposes transfer
access_control_core::transfer_admin(admin, new_admin_address);

// Step 2: New admin accepts
access_control_core::accept_pending_admin(new_admin);
```

## Key Functions

| Function | Description |
|----------|-------------|
| `require_role<T>(account)` | Assert account has role T |
| `has_role<T>(address)` | Check if address has role T |
| `grant_role<T>(admin, target)` | Grant role T to target |
| `revoke_role<T>(admin, target)` | Revoke role T from target |
| `get_roles(address)` | Get all roles for address |
| `transfer_admin(admin, new_admin)` | Propose admin transfer |
| `accept_pending_admin(new_admin)` | Accept admin transfer |

## Events

- `RoleGranted<T>` - Role granted
- `RoleRevoked<T>` - Role revoked  
- `AdminTransferProposed` - Admin transfer initiated
- `AdminTransferCompleted` - Admin transfer completed

## Error Codes

- `E_NOT_ADMIN` (0) - Caller not admin
- `E_ALREADY_HAS_ROLE` (1) - Role already assigned
- `E_NO_SUCH_ROLE` (2) - Role not found
- `E_ADMIN_ROLE_PROTECTED` (4) - Admin role cannot be manually managed

## Security Notes

- Admin role is protected - only transferable via two-step process
- Built-in Admin role type cannot be granted/revoked manually
- All operations emit events for audit trails