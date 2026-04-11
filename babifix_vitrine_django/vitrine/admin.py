from django.contrib import admin

from .models import ContactInquiry, FAQItem, HeroContent, Lead, Testimonial, VitrineStats


@admin.register(Lead)
class LeadAdmin(admin.ModelAdmin):
    list_display = ('email', 'created_at')
    search_fields = ('email',)


@admin.register(ContactInquiry)
class ContactInquiryAdmin(admin.ModelAdmin):
    list_display = ('email', 'subject', 'name', 'created_at')
    search_fields = ('email', 'subject', 'name', 'message')
    readonly_fields = ('created_at',)


@admin.register(FAQItem)
class FAQItemAdmin(admin.ModelAdmin):
    list_display = ('question', 'ordre_affichage', 'actif')
    list_editable = ('ordre_affichage', 'actif')
    search_fields = ('question', 'answer')
    ordering = ('ordre_affichage',)


@admin.register(Testimonial)
class TestimonialAdmin(admin.ModelAdmin):
    list_display = ('nom', 'role', 'ville', 'note', 'ordre_affichage', 'actif')
    list_editable = ('ordre_affichage', 'actif')
    search_fields = ('nom', 'texte')
    ordering = ('ordre_affichage',)


@admin.register(HeroContent)
class HeroContentAdmin(admin.ModelAdmin):
    list_display = ('titre', 'actif', 'updated_at')
    list_editable = ('actif',)


@admin.register(VitrineStats)
class VitrineStatsAdmin(admin.ModelAdmin):
    list_display = ('label', 'valeur', 'ordre_affichage', 'actif')
    list_editable = ('valeur', 'ordre_affichage', 'actif')
    ordering = ('ordre_affichage',)
