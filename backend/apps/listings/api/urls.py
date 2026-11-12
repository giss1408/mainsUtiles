from django.urls import path

from . import views

urlpatterns = [
    path("offer-categories", views.CategoriesView.as_view()),
    path("my-offers", views.MyOffersView.as_view()),
    path("my-offers/<uuid:pk>", views.MyOfferView.as_view()),
    path("my-offers/<uuid:pk>/send", views.SendView.as_view()),
    path("my-offers/<uuid:pk>/withdraw", views.WithdrawView.as_view()),
    path("my-offers/<uuid:pk>/copy", views.CopyView.as_view()),
]
