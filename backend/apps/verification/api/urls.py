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
    path("jobber/verification/contacts", jobber_views.ContactsView.as_view()),
    path("jobber/verification/contacts/<uuid:pk>", jobber_views.ContactDetailView.as_view()),
    path("jobber/verification/contacts/<uuid:pk>/code", jobber_views.ContactCodeView.as_view()),
    path("jobber/verification/contacts/<uuid:pk>/confirm", jobber_views.ContactConfirmView.as_view()),
    path("jobber/verification/contacts/<uuid:pk>/replace", jobber_views.ContactReplaceView.as_view()),
    path("jobber/verification/briefing", jobber_views.BriefingView.as_view()),
    path("jobber/verification/briefing/<uuid:card_id>/answer", jobber_views.BriefingAnswerView.as_view()),
]
