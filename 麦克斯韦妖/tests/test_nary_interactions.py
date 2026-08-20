import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from item_model import Axis, Item
from item_model.nary_interactions import (
    CombinationRegistry,
    CombinationRule,
    ContactGroup,
    ContactMode,
    MemberRequirement,
)


class CombinationInteractionTests(unittest.TestCase):
    def test_connected_combination_is_order_independent(self):
        registry = CombinationRegistry()
        registry.register(
            CombinationRule(
                rule_id="machine_water_crystal",
                members=(
                    MemberRequirement(kind="machine"),
                    MemberRequirement(kind="water"),
                    MemberRequirement(kind="crystal"),
                ),
                event="grow_crystal",
            )
        )

        machine = Item("机器", kind="machine")
        water = Item("水", kind="water")
        crystal = Item("晶核", kind="crystal")
        group = ContactGroup(
            (crystal, machine, water),
            frozenset({(0, 1), (1, 2)}),
        )

        self.assertEqual(registry.resolve(group), ("grow_crystal",))

    def test_repeated_kinds_are_supported(self):
        registry = CombinationRegistry()
        registry.register(
            CombinationRule(
                rule_id="two_metals_water",
                members=(
                    MemberRequirement(kind="metal"),
                    MemberRequirement(kind="metal"),
                    MemberRequirement(kind="water"),
                ),
                event="electrolysis",
            )
        )

        group = ContactGroup(
            (
                Item("金属甲", kind="metal"),
                Item("水", kind="water"),
                Item("金属乙", kind="metal"),
            ),
            frozenset({(0, 1), (1, 2)}),
        )
        self.assertEqual(registry.resolve(group), ("electrolysis",))

    def test_all_touching_requires_a_clique(self):
        registry = CombinationRegistry()
        registry.register(
            CombinationRule(
                rule_id="three_way_clique",
                members=(
                    MemberRequirement(kind="a"),
                    MemberRequirement(kind="b"),
                    MemberRequirement(kind="c"),
                ),
                event="three_way_clique",
                contact_mode=ContactMode.ALL_TOUCHING,
            )
        )

        chain = ContactGroup(
            (
                Item("A", kind="a"),
                Item("B", kind="b"),
                Item("C", kind="c"),
            ),
            frozenset({(0, 1), (1, 2)}),
        )
        self.assertEqual(registry.resolve(chain), ())

        clique = ContactGroup(
            chain.items,
            frozenset({(0, 1), (0, 2), (1, 2)}),
        )
        self.assertEqual(registry.resolve(clique), ("three_way_clique",))

    def test_member_properties_can_gate_a_combination(self):
        registry = CombinationRegistry()
        registry.register(
            CombinationRule(
                rule_id="hot_water_machine",
                members=(
                    MemberRequirement(
                        kind="machine",
                        axes=(AxisRequirement(Axis.TEMPERATURE, 1),),
                    ),
                    MemberRequirement(kind="water"),
                ),
                event="boil",
            )
        )

        hot_machine = Item(
            "热机器",
            {Axis.TEMPERATURE: 1},
            kind="machine",
        )
        cold_machine = Item(
            "冷机器",
            {Axis.TEMPERATURE: -1},
            kind="machine",
        )
        water = Item("水", kind="water")

        hot_group = ContactGroup((hot_machine, water), frozenset({(0, 1)}))
        cold_group = ContactGroup((cold_machine, water), frozenset({(0, 1)}))
        self.assertEqual(registry.resolve(hot_group), ("boil",))
        self.assertEqual(registry.resolve(cold_group), ())


if __name__ == "__main__":
    unittest.main()
