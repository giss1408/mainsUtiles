from rest_framework.permissions import BasePermission


class _HasRole(BasePermission):
    role = ""

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and user.role == self.role)


class IsHouseholder(_HasRole):
    role = "householder"


class IsJobber(_HasRole):
    role = "jobber"


class IsStaffMember(BasePermission):
    """A signed-in staff account. App users are refused whatever their token says."""

    perm: str | None = None

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated and user.role == "staff" and user.is_staff):
            return False
        return self.perm is None or user.has_perm(self.perm)


def HasStaffPermission(perm: str) -> type[IsStaffMember]:  # noqa: N802 - reads as a class at the call site
    """Build a permission class requiring a staff account that holds the Django permission `perm`."""
    return type("HasStaffPermission", (IsStaffMember,), {"perm": perm})
