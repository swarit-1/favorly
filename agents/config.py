"""Trellis config, scoped to grocery-favor tracking + reciprocity."""

import os
from dotenv import load_dotenv

load_dotenv()


def _bool(name: str, default: bool) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def _float(name: str, default: float) -> float:
    v = os.getenv(name)
    return float(v) if v else default


class Settings:
    DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/trellis")

    # Serverless changes three things: the schema is not re-applied on every
    # cold start, extraction runs inline instead of on a background worker
    # (a frozen invocation never drains a queue), and the connection pool is
    # kept tiny because every concurrent instance holds its own. Vercel sets
    # VERCEL=1 itself; set SERVERLESS explicitly anywhere else.
    SERVERLESS: bool = _bool("SERVERLESS", bool(os.getenv("VERCEL")))
    PORT: int = int(os.getenv("PORT", 8010))
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")

    MOCK_LLM: bool = _bool("MOCK_LLM", True)
    LLM_API_KEY: str = os.getenv("LLM_API_KEY", "")
    LLM_BASE_URL: str = os.getenv("LLM_BASE_URL", "https://api.openai.com/v1")
    LLM_MODEL: str = os.getenv("LLM_MODEL", "gpt-4o-mini")
    EMBEDDING_MODEL: str = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
    EMBEDDING_DIM: int = int(os.getenv("EMBEDDING_DIM", 1536))

    TEXTING_SERVICE_URL: str = os.getenv("TEXTING_SERVICE_URL", "http://localhost:9000")

    # extraction
    CONFIDENCE_FLOOR: float = _float("CONFIDENCE_FLOOR", 0.6)  # profile-display eligibility floor
    CORROBORATION_SIM_THRESHOLD: float = _float("CORROBORATION_SIM_THRESHOLD", 0.85)

    # canonicalization bands
    CANON_SNAP_THRESHOLD: float = _float("CANON_SNAP_THRESHOLD", 0.82)
    CANON_ADJUDICATE_THRESHOLD: float = _float("CANON_ADJUDICATE_THRESHOLD", 0.70)

    # decay + weights
    EDGE_DECAY_SECONDS: float = _float("EDGE_DECAY_SECONDS", 2592000.0)  # 30 days
    EDGE_WEIGHTS = {
        "favor": 1.0,
        "co_occurrence": 0.3,
    }

    PROFILE_CLAIM_CAP: int = 8



settings = Settings()
