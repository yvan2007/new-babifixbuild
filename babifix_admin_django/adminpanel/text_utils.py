"""Utilitaires texte partagés (anti-désintermédiation, etc.)."""
import re

_EMAIL_RE = re.compile(r"[\w.+\-]+@[\w\-]+\.[\w.\-]+")
# Suite de chiffres avec séparateurs éventuels (espaces, points, tirets, +).
_DIGIT_RUN_RE = re.compile(r"\+?\d[\d\s.\-]{5,}\d")


def mask_contacts(text: str) -> str:
    """Masque les numéros de téléphone et adresses e-mail dans un message de
    chat, pour décourager le contournement de la plateforme (les deux parties
    règlent et échangent DANS l'app). On ne masque que ce qui ressemble
    clairement à un contact : e-mails, et suites d'au moins 8 chiffres (un
    numéro ivoirien en fait 10 ; un montant comme 10000 n'en a que 5 → épargné).
    """
    if not text:
        return text
    text = _EMAIL_RE.sub("•••@•••", text)

    def _mask_num(m: "re.Match") -> str:
        digits = sum(c.isdigit() for c in m.group(0))
        return "☎ ••••••" if digits >= 8 else m.group(0)

    return _DIGIT_RUN_RE.sub(_mask_num, text)
