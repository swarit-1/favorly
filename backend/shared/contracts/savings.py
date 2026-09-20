"""Savings calculation models and constants for Favorly."""

from decimal import Decimal
from typing import Optional
from pydantic import BaseModel


# ============================================================================
# DELIVERY APP BENCHMARKS
# ============================================================================

class DeliveryAppBenchmarks:
    """Industry-average delivery app pricing for savings computation."""

    MARKUP_RATE = 0.20  # 20% item markup (Instacart average)
    DELIVERY_FEE = 5.99  # Average delivery fee
    SERVICE_FEE_RATE = 0.08  # 8% service fee
    TIP_RATE = 0.18  # 18% default tip assumption
    BULK_SAVINGS_RATE = 0.12  # Estimated savings from bulk purchasing


# ============================================================================
# RESPONSE MODELS
# ============================================================================

class RequesterSavings(BaseModel):
    """Savings for a user in the requester role."""

    fees_avoided_this_month: float
    fees_avoided_all_time: float
    trips_used_this_month: int
    delivery_app_estimate: float  # What it would cost on Instacart/DoorDash
    favorly_cost: float  # What they actually paid via Favorly


class CarrierSavings(BaseModel):
    """Earnings for a user in the carrier (shopper) role."""

    perks_earned_this_month: float  # Perk points
    bulk_savings_this_month: float  # Savings from combined orders
    total_earned_this_month: float
    trips_carried_this_month: int


class PersonalSavings(BaseModel):
    """Combined savings/earnings view for a user (may have both roles)."""

    requester_savings: Optional[RequesterSavings] = None
    carrier_savings: Optional[CarrierSavings] = None
    has_requester_data: bool = False
    has_carrier_data: bool = False


# ============================================================================
# COMPUTATION FUNCTIONS
# ============================================================================

def compute_requester_savings(
    subtotal: float,
    tax: float,
    favorly_total: float,
    items_count: int,
) -> RequesterSavings:
    """
    Compute requester savings by comparing Favorly cost to delivery-app estimate.

    Args:
        subtotal: Subtotal of items (before tax)
        tax: Tax paid
        favorly_total: Actual total paid via Favorly (subtotal + tax)
        items_count: Number of items in the order

    Returns:
        RequesterSavings with fees avoided and estimates
    """
    # Delivery app estimate: markup + delivery fee + service fee + tip
    markup = subtotal * DeliveryAppBenchmarks.MARKUP_RATE
    service_fee = subtotal * DeliveryAppBenchmarks.SERVICE_FEE_RATE
    tip = (subtotal + tax) * DeliveryAppBenchmarks.TIP_RATE

    delivery_app_estimate = (
        subtotal + tax + markup + DeliveryAppBenchmarks.DELIVERY_FEE + service_fee + tip
    )

    fees_avoided = max(0, delivery_app_estimate - favorly_total)

    return RequesterSavings(
        fees_avoided_this_month=round(fees_avoided, 2),
        fees_avoided_all_time=round(fees_avoided, 2),  # TODO: aggregate from DB
        trips_used_this_month=1,  # TODO: count from DB
        delivery_app_estimate=round(delivery_app_estimate, 2),
        favorly_cost=round(favorly_total, 2),
    )


def compute_carrier_savings(
    trips_carried: int,
    dollars_carried: float,
) -> CarrierSavings:
    """
    Compute carrier earnings from trips and bulk savings.

    Args:
        trips_carried: Number of trips completed as carrier
        dollars_carried: Total dollars of items carried

    Returns:
        CarrierSavings with perk earnings and bulk savings
    """
    # Perk value: nominal per-trip reward (e.g., $2 per trip)
    perk_value = trips_carried * 2.0

    # Bulk savings: carrier saves money by combining multiple requests
    bulk_savings = dollars_carried * DeliveryAppBenchmarks.BULK_SAVINGS_RATE

    total_earned = perk_value + bulk_savings

    return CarrierSavings(
        perks_earned_this_month=round(perk_value, 2),
        bulk_savings_this_month=round(bulk_savings, 2),
        total_earned_this_month=round(total_earned, 2),
        trips_carried_this_month=trips_carried,
    )
