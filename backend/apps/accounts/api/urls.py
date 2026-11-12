from django.urls import path

from . import views

urlpatterns = [
    path("enrolment/applications", views.ApplicationCreateView.as_view()),
    path("enrolment/applications/<uuid:id>", views.ApplicationStatusView.as_view()),
    path("enrolment/applications/<uuid:id>/confirm", views.ApplicationConfirmView.as_view()),
    path("auth/challenge", views.ChallengeView.as_view()),
    path("auth/token", views.TokenView.as_view()),
    path("auth/refresh", views.RefreshView.as_view()),
    path("me", views.MeView.as_view()),
]
