"""Insurance eligibility and guarantee schemas."""

from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class InsuranceStatus(BaseModel):
    """Insurance eligibility status for a user."""

    user_id: str
    active: bool
    trips_carried_this_month: int
    guaranteed_threshold: int = 3  # Carrying 3+ times/month qualifies
    expires_at: Optional[datetime] = None
    karma_multiplier_when_active: int = 2
    guarantee_window_hours: int = 48


class GuaranteedRequest(BaseModel):
    """A request that is guaranteed-filled by the building."""

    id: str
    requester_id: str
    request_items: str  # JSON description of items
    guarantee_deadline: datetime
    filled_by: Optional[str] = None  # null = building/assistant covers it
    filled_at: Optional[datetime] = None
    coverage_cost: float
    created_at: datetime


def check_insurance_eligibility(trips_carried_this_month: int) -> bool:
    """
    Check if user qualifies for insurance.

    Requirement: Carry 3+ times in the current month.
    """
    return trips_carried_this_month >= 3
