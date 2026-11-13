from django.urls import path

from . import jobber_views, views

urlpatterns = [
    path("verification", views.ChecklistView.as_view()),
    path("verification/identity", views.IdentityView.as_view()),
    path("verification/address", views.AddressView.as_view()),
    path("verification/home-location", views.HomeLocationView.as_view()),
    path("jobber/verification", jobber_views.JobberChecklistView.as_view()),
    path("jobber/verification/identity", jobber_views.JobberIdentityView.as_view()),
    path("jobber/verification/guarantor", jobber_views.JobberGuarantorView.as_view()),
]
