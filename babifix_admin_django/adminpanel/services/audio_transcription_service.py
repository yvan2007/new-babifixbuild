"""Service de transcription automatique des notes vocales BABIFIX.

Supporte en cascade (selon les cles configurees en environnement) :
  1. Groq Whisper (`GROQ_API_KEY`, modele `whisper-large-v3-turbo`, tier gratuit rapide)
  2. OpenAI Whisper (`OPENAI_API_KEY`, modele `whisper-1`)
  3. Gemini Multimodal Audio (`GEMINI_API_KEY`, modele `gemini-2.5-flash`)

Sans cle configuree : renvoie proprement `configured=False` sans jamais lever d'erreur.
"""

from __future__ import annotations

import base64
import logging
import mimetypes
import os
from pathlib import Path
from typing import Any

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

_MAX_AUDIO_BYTES = 12 * 1024 * 1024


def stt_provider_name() -> str:
    """Indique le fournisseur STT actif (ou chaine vide si aucun configure)."""
    if (os.getenv("GROQ_API_KEY") or getattr(settings, "GROQ_API_KEY", "")).strip():
        return "groq_whisper"
    if (os.getenv("OPENAI_API_KEY") or getattr(settings, "OPENAI_API_KEY", "")).strip():
        return "openai_whisper"
    if (os.getenv("GEMINI_API_KEY") or getattr(settings, "GEMINI_API_KEY", "")).strip():
        return "gemini_audio"
    return ""


def _read_audio_bytes(file_path_or_url: str) -> tuple[bytes | None, str, str]:
    """Charge l'audio depuis MEDIA_ROOT ou une URL HTTPS autorisee.

    Retourne (raw_bytes, filename, mime_type).
    """
    src = (file_path_or_url or "").strip()
    if not src:
        return None, "", ""

    # Chemin local ou URL /media/...
    if src.startswith("/media/") or not src.startswith(("http://", "https://")):
        rel = src.replace("/media/", "", 1).lstrip("/\\")
        if ".." in rel:
            return None, "", ""
        full = Path(settings.MEDIA_ROOT) / rel
        if not full.exists() or not full.is_file():
            # Verifier aussi si chemin absolu dans MEDIA_ROOT
            cand = Path(src)
            try:
                cand_res = cand.resolve()
                media_res = Path(settings.MEDIA_ROOT).resolve()
                if str(cand_res).startswith(str(media_res)) and cand_res.is_file():
                    full = cand_res
                else:
                    return None, "", ""
            except Exception:
                return None, "", ""
        if full.stat().st_size > _MAX_AUDIO_BYTES:
            return None, "", ""
        mime = mimetypes.guess_type(str(full))[0] or "audio/mp4"
        return full.read_bytes(), full.name, mime

    # URL distante (ex: Cloudinary)
    try:
        resp = requests.get(src, timeout=15)
        if resp.status_code != 200:
            return None, "", ""
        raw = resp.content
        if not raw or len(raw) > _MAX_AUDIO_BYTES:
            return None, "", ""
        fname = src.split("?", 1)[0].rsplit("/", 1)[-1] or "voice.m4a"
        mime = resp.headers.get("Content-Type", "").split(";", 1)[0].strip() or (
            mimetypes.guess_type(fname)[0] or "audio/mp4"
        )
        return raw, fname, mime
    except Exception as exc:
        logger.warning("STT: lecture audio distante echouee (%s)", exc)
        return None, "", ""


def _transcribe_whisper_compatible(
    endpoint: str,
    api_key: str,
    model: str,
    raw: bytes,
    filename: str,
    mime: str,
    language: str,
) -> str:
    resp = requests.post(
        endpoint,
        headers={"Authorization": f"Bearer {api_key}"},
        files={"file": (filename, raw, mime)},
        data={
            "model": model,
            "language": language,
            "response_format": "json",
        },
        timeout=30,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")
    data = resp.json()
    return str(data.get("text") or "").strip()


def _transcribe_gemini(
    api_key: str,
    raw: bytes,
    mime: str,
    language: str,
) -> str:
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"gemini-2.5-flash:generateContent?key={api_key}"
    )
    b64 = base64.b64encode(raw).decode("ascii")
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "text": (
                            f"Transcris fidelement cette note vocale en {language} "
                            "sans commentaire ni mise en forme, uniquement le texte parle."
                        )
                    },
                    {"inline_data": {"mime_type": mime, "data": b64}},
                ]
            }
        ]
    }
    resp = requests.post(endpoint, json=payload, timeout=30)
    if resp.status_code != 200:
        raise RuntimeError(f"Gemini HTTP {resp.status_code}: {resp.text[:200]}")
    data = resp.json()
    candidates = data.get("candidates") or []
    if not candidates:
        return ""
    parts = ((candidates[0].get("content") or {}).get("parts")) or []
    return " ".join(str(p.get("text") or "").strip() for p in parts).strip()


def transcribe_audio_source(
    file_path_or_url: str,
    *,
    language: str = "fr",
) -> dict[str, Any]:
    """Transcrit une note vocale en francais. Ne leve jamais d'exception."""
    provider = stt_provider_name()
    if not provider:
        return {
            "ok": False,
            "configured": False,
            "provider": "",
            "transcript": "",
            "reason": "stt_not_configured",
            "detail": (
                "Transcription automatique non activee sur le serveur "
                "(definissez GROQ_API_KEY, OPENAI_API_KEY ou GEMINI_API_KEY)."
            ),
        }

    raw, fname, mime = _read_audio_bytes(file_path_or_url)
    if not raw:
        return {
            "ok": False,
            "configured": True,
            "provider": provider,
            "transcript": "",
            "reason": "audio_unreadable",
            "detail": "Fichier audio introuvable ou trop volumineux (max 12 Mo).",
        }

    try:
        if provider == "groq_whisper":
            key = (os.getenv("GROQ_API_KEY") or getattr(settings, "GROQ_API_KEY", "")).strip()
            text = _transcribe_whisper_compatible(
                "https://api.groq.com/openai/v1/audio/transcriptions",
                key,
                "whisper-large-v3-turbo",
                raw,
                fname,
                mime,
                language,
            )
        elif provider == "openai_whisper":
            key = (os.getenv("OPENAI_API_KEY") or getattr(settings, "OPENAI_API_KEY", "")).strip()
            text = _transcribe_whisper_compatible(
                "https://api.openai.com/v1/audio/transcriptions",
                key,
                "whisper-1",
                raw,
                fname,
                mime,
                language,
            )
        else:
            key = (os.getenv("GEMINI_API_KEY") or getattr(settings, "GEMINI_API_KEY", "")).strip()
            text = _transcribe_gemini(key, raw, mime, language)

        return {
            "ok": True,
            "configured": True,
            "provider": provider,
            "transcript": text[:4000],
            "reason": "ok" if text else "empty_audio",
        }
    except Exception as exc:
        logger.warning("STT transcription echouee (%s): %s", provider, exc)
        return {
            "ok": False,
            "configured": True,
            "provider": provider,
            "transcript": "",
            "reason": "stt_error",
            "detail": "Transcription temporairement indisponible.",
        }
