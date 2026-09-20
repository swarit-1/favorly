"""Referral and invite-code endpoints."""

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthCredentials

from shared.contracts.referrals import ReferralStats, ReferralReward

router = APIRouter(prefix="/referrals", tags=["referrals"])
security = HTTPBearer()


@router.get("/stats/{user_id}")
async def get_referral_stats(user_id: str, credentials: HTTPAuthCredentials = Depends(security)):
    """
    GET /referrals/stats/{user_id}
    Get referral statistics for a user.
    Returns invite code, referral count, and total karma earned.
    """
    # TODO: Query database for user's referrals
    # For now, return empty stats
    return ReferralStats(
        user_id=user_id,
        invite_code=f"INVITE_{user_id[:4].upper()}",
        total_referred=0,
        total_karma_earned=0,
        referrals=[],
    ).to_json()


@router.post("/check-earned/{user_id}")
async def check_new_referral_rewards(
    user_id: str, credentials: HTTPAuthCredentials = Depends(security)
):
    """
    POST /referrals/check-earned/{user_id}
    Check if user just earned a referral reward (invitee completed first favor).
    Called after settlements are created.
    """
    # TODO: Query for recent settlements by this user
    # Check if any settlers were invited by others
    # If so, create ReferralReward and return it
    return {"earned_rewards": []}
