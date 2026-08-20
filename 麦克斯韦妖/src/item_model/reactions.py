from __future__ import annotations

from .model import Axis, Item, Process, reconcile_processes


def _ignite(item: Item) -> None:
    if item.get(Axis.COMBUSTIBILITY) == 1:
        item.processes.add(Process.BURNING)


def _freeze(item: Item) -> None:
    if item.get(Axis.FREEZABILITY) == 1:
        item.processes.add(Process.FROZEN)


def resolve_intrinsic_reactions(item: Item) -> None:
    """处理同一物品内部已经同时具备的触发条件。"""
    reconcile_processes(item)
    if item.get(Axis.TEMPERATURE) == 1 and item.get(Axis.COMBUSTIBILITY) == 1:
        _ignite(item)
    if item.get(Axis.TEMPERATURE) == -1 and item.get(Axis.FREEZABILITY) == 1:
        _freeze(item)


def resolve_contact(left: Item, right: Item) -> None:
    """处理两个物品直接接触后的即时反应。

    属性转移仍然必须由玩家手动调用 transfer；这里仅处理接触反应。
    """
    resolve_intrinsic_reactions(left)
    if right is not left:
        resolve_intrinsic_reactions(right)

        if left.get(Axis.TEMPERATURE) == 1 and right.get(Axis.COMBUSTIBILITY) == 1:
            _ignite(right)
        if right.get(Axis.TEMPERATURE) == 1 and left.get(Axis.COMBUSTIBILITY) == 1:
            _ignite(left)

        if left.get(Axis.TEMPERATURE) == -1 and right.get(Axis.FREEZABILITY) == 1:
            _freeze(right)
        if right.get(Axis.TEMPERATURE) == -1 and left.get(Axis.FREEZABILITY) == 1:
            _freeze(left)

        if Process.BURNING in left.processes and right.get(Axis.COMBUSTIBILITY) == -1:
            left.processes.discard(Process.BURNING)
        if Process.BURNING in right.processes and left.get(Axis.COMBUSTIBILITY) == -1:
            right.processes.discard(Process.BURNING)

        if Process.FROZEN in left.processes and right.get(Axis.FREEZABILITY) == -1:
            left.processes.discard(Process.FROZEN)
        if Process.FROZEN in right.processes and left.get(Axis.FREEZABILITY) == -1:
            right.processes.discard(Process.FROZEN)
