from django.urls import path

from . import jobber_views, jobs_views, payments_views, staff_views, views

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
    path("my-bookings/<uuid:pk>/check-in", jobs_views.CheckInView.as_view()),
    path("my-bookings/<uuid:pk>/check-out", jobs_views.CheckOutView.as_view()),
    path("my-bookings/<uuid:pk>/report", jobs_views.JobberReportView.as_view()),
    path("my-bookings/<uuid:pk>/review", jobs_views.JobberReviewView.as_view()),
    path("my-offers/<uuid:pk>/booking/confirm", jobs_views.ConfirmView.as_view()),
    path("my-offers/<uuid:pk>/booking/report", jobs_views.HouseholderReportView.as_view()),
    path("my-offers/<uuid:pk>/booking/review", jobs_views.HouseholderReviewView.as_view()),
    path("staff/payments", staff_views.PaymentQueueView.as_view()),
    path("staff/payments/<uuid:pk>", staff_views.PaymentDetailView.as_view()),
    path("staff/payments/<uuid:pk>/proof", staff_views.PaymentProofView.as_view()),
    path("staff/payments/<uuid:pk>/confirm", staff_views.PaymentConfirmView.as_view()),
    path("staff/payments/<uuid:pk>/refuse", staff_views.PaymentRefuseView.as_view()),
    path("staff/payments/<uuid:pk>/refund", staff_views.PaymentRefundView.as_view()),
]
