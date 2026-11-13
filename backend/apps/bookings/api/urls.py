from django.urls import path

from . import jobber_views, views

urlpatterns = [
    path("offers/<uuid:pk>/apply", jobber_views.ApplyView.as_view()),
    path("my-applications", jobber_views.MyApplicationsView.as_view()),
    path("my-applications/<uuid:pk>/withdraw", jobber_views.WithdrawView.as_view()),
    path("my-bookings", jobber_views.MyBookingsView.as_view()),
    path("my-offers/<uuid:pk>/applicants", views.ApplicantsView.as_view()),
    path("my-offers/<uuid:pk>/applicants/<uuid:application_id>/accept", views.AcceptView.as_view()),
]
