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
