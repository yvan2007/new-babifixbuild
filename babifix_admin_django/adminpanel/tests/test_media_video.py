"""MediaService — support vidéo du problème (nouvelle fonctionnalité).

Mêmes garanties que la note vocale déjà en place : détection par MIME ou par
extension de fichier (certains clients n'envoient pas de content-type fiable),
plafond de taille, et retombée sur RawMediaCloudinaryStorage (Cloudinary
refuse les fichiers non-image sur son storage par défaut).
"""
import io

from django.test import TestCase

from adminpanel.services.media_service import (
    MAX_VIDEO_BYTES,
    MediaUploadError,
    MediaService,
)


class _FakeUploadedFile:
    """Simule un InMemoryUploadedFile Django (content_type + name + read())."""

    def __init__(self, content: bytes, content_type: str, name: str):
        self._content = content
        self.content_type = content_type
        self.name = name

    def read(self):
        return self._content


class StoreVideoBytesTest(TestCase):
    def test_rejette_le_contenu_vide(self):
        with self.assertRaises(MediaUploadError):
            MediaService.store_video_bytes(b"", "mp4", user_id=1)

    def test_rejette_un_fichier_trop_lourd(self):
        content = b"x" * (MAX_VIDEO_BYTES + 1)
        with self.assertRaises(MediaUploadError):
            MediaService.store_video_bytes(content, "mp4", user_id=1)

    def test_accepte_un_fichier_dans_la_limite(self):
        url = MediaService.store_video_bytes(b"fake-mp4-bytes", "mp4", user_id=7)
        self.assertTrue(url)
        self.assertTrue(url.endswith(".mp4"))


class StoreUploadVideoDetectionTest(TestCase):
    """Détection MIME correcte : la vidéo va au bon chemin (pas l'image)."""

    def test_detecte_video_par_mime(self):
        f = _FakeUploadedFile(b"fake-mp4-bytes", "video/mp4", "IMG_0001.mp4")
        url = MediaService.store_upload(f, user_id=3)
        self.assertTrue(url.endswith(".mp4"))

    def test_detecte_video_par_extension_si_mime_absent(self):
        # Cas réel : certains clients envoient un content-type générique
        # (application/octet-stream) et seul le nom de fichier est fiable.
        f = _FakeUploadedFile(b"fake-mov-bytes", "application/octet-stream", "clip.mov")
        url = MediaService.store_upload(f, user_id=3)
        self.assertTrue(url.endswith(".mov"))

    def test_ne_confond_pas_video_et_audio(self):
        # Garde-fou : une note vocale (.m4a) ne doit PAS partir dans le
        # chemin vidéo, et réciproquement.
        f = _FakeUploadedFile(b"fake-audio-bytes", "audio/mp4", "vn_123.m4a")
        url = MediaService.store_upload(f, user_id=3)
        self.assertTrue(url.endswith(".m4a"))

    def test_video_trop_lourde_leve_une_erreur_via_store_upload(self):
        content = b"x" * (MAX_VIDEO_BYTES + 1)
        f = _FakeUploadedFile(content, "video/mp4", "long.mp4")
        with self.assertRaises(MediaUploadError):
            MediaService.store_upload(f, user_id=3)
