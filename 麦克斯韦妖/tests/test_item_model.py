import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from item_model import Axis, Item, Process, resolve_contact, transfer


class TransferTests(unittest.TestCase):
    def test_flammable_to_ordinary(self):
        source = Item("木头", {Axis.COMBUSTIBILITY: 1})
        target = Item("水", {Axis.COMBUSTIBILITY: 0})

        transfer(source, target, Axis.COMBUSTIBILITY)

        self.assertEqual(source.get(Axis.COMBUSTIBILITY), 0)
        self.assertEqual(target.get(Axis.COMBUSTIBILITY), 1)

    def test_ordinary_to_extinguisher(self):
        source = Item("普通石头", {Axis.COMBUSTIBILITY: 0})
        target = Item("水", {Axis.COMBUSTIBILITY: 0})

        transfer(source, target, Axis.COMBUSTIBILITY)

        self.assertEqual(source.get(Axis.COMBUSTIBILITY), -1)
        self.assertEqual(target.get(Axis.COMBUSTIBILITY), 1)

    def test_extinguisher_receiving_flammability_returns_to_ordinary(self):
        source = Item("木头", {Axis.COMBUSTIBILITY: 1})
        target = Item("灭火物", {Axis.COMBUSTIBILITY: -1})

        transfer(source, target, Axis.COMBUSTIBILITY)

        self.assertEqual(source.get(Axis.COMBUSTIBILITY), 0)
        self.assertEqual(target.get(Axis.COMBUSTIBILITY), 0)


class ContactReactionTests(unittest.TestCase):
    def test_hot_combustible_contact_starts_burning(self):
        hot = Item("烫石头", {Axis.TEMPERATURE: 1})
        wood = Item("木头", {Axis.COMBUSTIBILITY: 1})

        resolve_contact(hot, wood)

        self.assertIn(Process.BURNING, wood.processes)

    def test_hot_and_combustible_same_item_starts_burning(self):
        wood = Item("烫木头", {Axis.TEMPERATURE: 1, Axis.COMBUSTIBILITY: 1})

        resolve_contact(wood, wood)

        self.assertIn(Process.BURNING, wood.processes)

    def test_cold_freezable_contact_creates_ice(self):
        cold = Item("冷物", {Axis.TEMPERATURE: -1})
        water = Item("水", {Axis.FREEZABILITY: 1})

        resolve_contact(cold, water)

        self.assertIn(Process.FROZEN, water.processes)

    def test_stone_does_not_freeze(self):
        cold = Item("冷物", {Axis.TEMPERATURE: -1})
        stone = Item("石头", {Axis.FREEZABILITY: 0})

        resolve_contact(cold, stone)

        self.assertNotIn(Process.FROZEN, stone.processes)

    def test_anti_freeze_unfreezes_ice(self):
        ice = Item("冰", {Axis.FREEZABILITY: 1}, {Process.FROZEN})
        anti_freeze = Item("阻止结冰物", {Axis.FREEZABILITY: -1})

        resolve_contact(ice, anti_freeze)

        self.assertNotIn(Process.FROZEN, ice.processes)


if __name__ == "__main__":
    unittest.main()
