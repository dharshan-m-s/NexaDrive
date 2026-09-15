# Phase 3 — Users, Sharing & Permissions

Phase 3 adds the multi-user security layer.

## Users
- Admin-only user listing and creation
- Admin-only role/disabled updates
- Passwords continue to use Argon2id
- Disabled users cannot log in

## Sharing
- Share a file or folder with a server user
- Read and write permissions
- Optional public download link with random 64-character token
- Optional expiration on shares
- Owner can revoke a share
- Recipient can browse shared folders
- Recipient can download shared files
- Write shares can rename, move, and send shared items to the owner's Trash inside the granted subtree

## Routes
- `GET /api/admin/users`
- `POST /api/admin/users`
- `PUT /api/admin/users/:id`
- `GET /api/shares`
- `POST /api/shares`
- `DELETE /api/shares?id=<uuid>`
- `GET /api/shared`
- `GET /api/shared/items?share_id=<uuid>&path=<relative>`
- `GET /api/shared/download?share_id=<uuid>&path=<relative>`
- `POST /api/shared/action`
- `GET /api/share/:token/download?path=<relative>` (public link)

All shared-item paths are resolved relative to the original owner's shared root and are checked against that root before filesystem access.
