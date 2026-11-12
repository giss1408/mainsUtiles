from django.urls import include, path

urlpatterns = [
    path("", include("apps.accounts.api.urls")),
    path("staff/", include("apps.accounts.api.staff_urls")),
    path("", include("apps.verification.api.urls")),
    path("", include("apps.listings.api.urls")),
]
