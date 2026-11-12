from django.urls import path

from . import staff_views as views

urlpatterns = [
    path("devices", views.StaffDeviceView.as_view()),
    path("auth/login", views.StaffLoginView.as_view()),
    path("me", views.StaffMeView.as_view()),
    path("enrolments", views.EnrolmentQueueView.as_view()),
    path("enrolments/<uuid:id>", views.EnrolmentDetailView.as_view()),
    path("enrolments/<uuid:id>/approve", views.EnrolmentApproveView.as_view()),
    path("enrolments/<uuid:id>/refuse", views.EnrolmentRefuseView.as_view()),
    path("enrolments/<uuid:id>/hold", views.EnrolmentHoldView.as_view()),
    path("enrolments/<uuid:id>/send", views.EnrolmentSendView.as_view()),
]
