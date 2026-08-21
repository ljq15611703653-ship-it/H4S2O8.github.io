import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from item_model import Axis, Item
from item_model.pair_interactions import AxisRequirement, InteractionRegistry, PairRule


class PairInteractionTests(unittest.TestCase):
    def test_symmetric_rule_matches_both_orders(self):
        registry = InteractionRegistry()
        registry.register(
            PairRule(
                rule_id="furnace_water",
                left_kind="furnace",
                right_kind="water",
                event="heat_water",
                symmetric=True,
            )
        )

        furnace = Item("熔炉", kind="furnace")
        water = Item("水", kind="water")

        self.assertEqual(registry.resolve(furnace, water), ("heat_water",))
        self.assertEqual(registry.resolve(water, furnace), ("heat_water",))

    def test_axis_requirements_filter_pair(self):
        registry = InteractionRegistry()
        registry.register(
            PairRule(
                rule_id="hot_machine_water",
                left_kind="machine",
                right_kind="water",
                event="boil_water",
                left_axes=(AxisRequirement(Axis.TEMPERATURE, 1),),
            )
        )

        hot_machine = Item("热机器", {Axis.TEMPERATURE: 1}, kind="machine")
        cold_machine = Item("冷机器", {Axis.TEMPERATURE: -1}, kind="machine")
        water = Item("水", kind="water")

        self.assertEqual(registry.resolve(hot_machine, water), ("boil_water",))
        self.assertEqual(registry.resolve(cold_machine, water), ())


if __name__ == "__main__":
    unittest.main()
