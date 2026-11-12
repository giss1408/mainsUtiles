from django.urls import path

from . import views

urlpatterns = [
    path("enrolment/applications", views.ApplicationCreateView.as_view()),
    path("enrolment/applications/<uuid:id>", views.ApplicationStatusView.as_view()),
    path("enrolment/applications/<uuid:id>/confirm", views.ApplicationConfirmView.as_view()),
]
