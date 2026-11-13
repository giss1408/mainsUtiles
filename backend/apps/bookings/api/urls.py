from django.urls import path

from . import jobber_views, payments_views, views

urlpatterns = [
    path("offers/<uuid:pk>/apply", jobber_views.ApplyView.as_view()),
    path("my-applications", jobber_views.MyApplicationsView.as_view()),
    path("my-applications/<uuid:pk>/withdraw", jobber_views.WithdrawView.as_view()),
    path("my-bookings", jobber_views.MyBookingsView.as_view()),
    path("my-offers/<uuid:pk>/applicants", views.ApplicantsView.as_view()),
    path("my-offers/<uuid:pk>/applicants/<uuid:application_id>/accept", views.AcceptView.as_view()),
    path("my-offers/<uuid:pk>/booking", payments_views.BookingView.as_view()),
    path("my-offers/<uuid:pk>/booking/payment", payments_views.PaymentView.as_view()),
    path("my-offers/<uuid:pk>/booking/photo", payments_views.PhotoView.as_view()),
    path("my-offers/<uuid:pk>/booking/cancel", payments_views.CancelView.as_view()),
    path("my-bookings/<uuid:pk>/address", payments_views.AddressView.as_view()),
    path("my-bookings/<uuid:pk>/cancel", payments_views.JobberCancelView.as_view()),
]
