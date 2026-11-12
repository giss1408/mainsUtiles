from django.urls import path

from . import views

urlpatterns = [
    path("verification", views.ChecklistView.as_view()),
    path("verification/identity", views.IdentityView.as_view()),
    path("verification/address", views.AddressView.as_view()),
    path("verification/home-location", views.HomeLocationView.as_view()),
]
