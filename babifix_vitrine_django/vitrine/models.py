from django.db import models


class Lead(models.Model):
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.email


class ContactInquiry(models.Model):
    """Messages envoyés depuis le formulaire Contact de la vitrine."""

    name = models.CharField(max_length=120)
    email = models.EmailField()
    subject = models.CharField(max_length=200)
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Message contact vitrine'
        verbose_name_plural = 'Messages contact vitrine'

    def __str__(self):
        return f'{self.email} — {self.subject[:40]}'


class FAQItem(models.Model):
    """FAQ pour la page vitrine."""

    question = models.CharField(max_length=500)
    answer = models.TextField()
    ordre_affichage = models.PositiveIntegerField(default=0)
    actif = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['ordre_affichage', '-created_at']
        verbose_name = 'FAQ'
        verbose_name_plural = 'FAQs'

    def __str__(self):
        return self.question[:80]


class Testimonial(models.Model):
    """Témoignages affichés sur la vitrine."""

    nom = models.CharField(max_length=120)
    role = models.CharField(max_length=200, blank=True, default='')
    ville = models.CharField(max_length=120, blank=True, default='')
    texte = models.TextField()
    note = models.PositiveSmallIntegerField(default=5, help_text='Note sur 5')
    avatar_url = models.CharField(max_length=500, blank=True, default='')
    actif = models.BooleanField(default=True)
    ordre_affichage = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['ordre_affichage', '-created_at']
        verbose_name = 'Témoignage'
        verbose_name_plural = 'Témoignages'

    def __str__(self):
        return f'{self.nom} — {self.role}'


class HeroContent(models.Model):
    """Contenu de la section héros de la vitrine."""

    titre = models.CharField(max_length=200, blank=True, default='')
    soustitre = models.TextField(blank=True, default='')
    actif = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Contenu héros'
        verbose_name_plural = 'Contenus héros'

    def __str__(self):
        return self.titre or 'Héros'


class VitrineStats(models.Model):
    """Statistiques dynamiques pour la vitrine."""

    label = models.CharField(max_length=100, unique=True)
    valeur = models.CharField(max_length=50, help_text='Ex: 10,000+')
    ordre_affichage = models.PositiveIntegerField(default=0)
    actif = models.BooleanField(default=True)

    class Meta:
        ordering = ['ordre_affichage']
        verbose_name = 'Statistique vitrine'
        verbose_name_plural = 'Statistiques vitrine'

    def __str__(self):
        return f'{self.label}: {self.valeur}'
