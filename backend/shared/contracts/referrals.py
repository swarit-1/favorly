"""Invite-code and referral reward models."""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class ReferralReward:
    """A completed referral: invitee did their first favor."""

    id: str
    referrer_id: str  # who invited
    referree_id: str  # who was invited
    karma_earned: int  # karma granted to referrer
    completed_favor_id: str  # settlement/trip ID that triggered the reward
    earned_at: datetime
    description: str = "Recruit-a-neighbor bonus"

    def to_json(self):
        return {
            "id": self.id,
            "referrer_id": self.referrer_id,
            "referree_id": self.referree_id,
            "karma_earned": self.karma_earned,
            "completed_favor_id": self.completed_favor_id,
            "earned_at": self.earned_at.isoformat(),
            "description": self.description,
        }

    @classmethod
    def from_json(cls, data: dict) -> "ReferralReward":
        return cls(
            id=data["id"],
            referrer_id=data["referrer_id"],
            referree_id=data["referree_id"],
            karma_earned=data["karma_earned"],
            completed_favor_id=data["completed_favor_id"],
            earned_at=datetime.fromisoformat(data["earned_at"]),
            description=data.get("description", "Recruit-a-neighbor bonus"),
        )


@dataclass
class ReferralStats:
    """Referral statistics for a user."""

    user_id: str
    invite_code: str
    total_referred: int
    total_karma_earned: int
    referrals: list[ReferralReward] = field(default_factory=list)

    def to_json(self):
        return {
            "user_id": self.user_id,
            "invite_code": self.invite_code,
            "total_referred": self.total_referred,
            "total_karma_earned": self.total_karma_earned,
            "referrals": [r.to_json() for r in self.referrals],
        }

    @classmethod
    def from_json(cls, data: dict) -> "ReferralStats":
        return cls(
            user_id=data["user_id"],
            invite_code=data["invite_code"],
            total_referred=data["total_referred"],
            total_karma_earned=data["total_karma_earned"],
            referrals=[
                ReferralReward.from_json(r) for r in data.get("referrals", [])
            ],
        )
