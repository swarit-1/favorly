"""Collective unlocks and building-wide milestones."""

from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from enum import Enum


class UnlockType(str, Enum):
    """Types of collective unlocks/rewards."""
    PIZZA_NIGHT = "pizza_night"
    COFFEE_MACHINE = "coffee_machine"
    LOBBY_UPGRADE = "lobby_upgrade"
    COMMUNITY_LUNCH = "community_lunch"


class UnlockTier(BaseModel):
    """Milestone tier defining when an unlock triggers."""
    threshold: int  # favors needed
    unlock_type: UnlockType
    reward_description: str
    reward_emoji: str


# Define unlock tiers
UNLOCK_TIERS = [
    UnlockTier(
        threshold=25,
        unlock_type=UnlockType.PIZZA_NIGHT,
        reward_description="Circle achieves 25 favors! Property manager funds pizza night.",
        reward_emoji="🍕",
    ),
    UnlockTier(
        threshold=50,
        unlock_type=UnlockType.COFFEE_MACHINE,
        reward_description="Circle achieves 50 favors! Building upgrades lobby coffee machine.",
        reward_emoji="☕",
    ),
    UnlockTier(
        threshold=100,
        unlock_type=UnlockType.COMMUNITY_LUNCH,
        reward_description="Circle achieves 100 favors! Community lunch celebration.",
        reward_emoji="🎉",
    ),
]


class CircleUnlock(BaseModel):
    """A claimed collective unlock/milestone reward."""
    id: str
    circle_id: str
    unlock_type: UnlockType
    reward_description: str
    favors_at_unlock: int
    claimed_at: datetime


class CircleUnlockStatus(BaseModel):
    """Circle-wide unlock progress and claimed rewards."""
    circle_id: str
    favors_this_month: int
    progress_percentage: float  # 0-100, capped at 100
    next_milestone_threshold: Optional[int]  # null if all unlocked
    next_milestone_description: Optional[str]
    next_milestone_favors_remaining: Optional[int]
    claimed_unlocks: List[CircleUnlock]
    available_unlocks: List[UnlockType]  # not yet claimed


def compute_unlock_progress(
    favors_this_month: int, circle_id: str, claimed_unlock_types: List[UnlockType]
) -> dict:
    """
    Compute circle unlock progress.

    Returns dict with favors_this_month, progress_percentage, next_milestone_*, claimed, available.
    """
    # Sort tiers by threshold
    sorted_tiers = sorted(UNLOCK_TIERS, key=lambda t: t.threshold)

    # Find next unclaimed milestone
    next_milestone = None
    for tier in sorted_tiers:
        if tier.unlock_type not in claimed_unlock_types:
            next_milestone = tier
            break

    # Compute progress
    max_threshold = sorted_tiers[-1].threshold if sorted_tiers else 100
    progress_pct = min(100.0, (favors_this_month / max_threshold) * 100)

    next_threshold = next_milestone.threshold if next_milestone else None
    next_description = (
        next_milestone.reward_description if next_milestone else None
    )
    next_remaining = (
        max(0, next_milestone.threshold - favors_this_month)
        if next_milestone
        else None
    )

    # Available unlocks are those we've hit the threshold for but haven't claimed yet
    available = [
        tier.unlock_type
        for tier in sorted_tiers
        if tier.threshold <= favors_this_month
        and tier.unlock_type not in claimed_unlock_types
    ]

    return {
        "favors_this_month": favors_this_month,
        "progress_percentage": round(progress_pct, 1),
        "next_milestone_threshold": next_threshold,
        "next_milestone_description": next_description,
        "next_milestone_favors_remaining": next_remaining,
        "available_unlocks": available,
    }
