from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Axis(str, Enum):
    TEMPERATURE = "temperature"
    COMBUSTIBILITY = "combustibility"
    FREEZABILITY = "freezability"
    WEIGHT = "weight"
    DEFORMATION = "deformation"


class Process(str, Enum):
    BURNING = "burning"
    FROZEN = "frozen"


def _validate_value(value: int) -> None:
    if value not in (-1, 0, 1):
        raise ValueError("物性值必须是 -1、0 或 +1")


@dataclass
class Item:
    name: str
    axes: dict[Axis, int] = field(default_factory=dict)
    processes: set[Process] = field(default_factory=set)
    kind: str = "generic"

    def __post_init__(self) -> None:
        for axis in Axis:
            self.axes.setdefault(axis, 0)
        for value in self.axes.values():
            _validate_value(value)

    def get(self, axis: Axis) -> int:
        return self.axes[axis]

    def set(self, axis: Axis, value: int) -> None:
        _validate_value(value)
        self.axes[axis] = value


def reconcile_processes(item: Item) -> None:
    """属性被移走后，立即清理不再成立的过程状态。"""
    if item.get(Axis.COMBUSTIBILITY) != 1:
        item.processes.discard(Process.BURNING)
    if item.get(Axis.FREEZABILITY) != 1:
        item.processes.discard(Process.FROZEN)


def transfer(source: Item, target: Item, axis: Axis, direction: int = 1) -> None:
    """转移一个方向的物性单位，而不是复制属性。

    direction=1 表示转移正向单位，例如可燃性或弹性。
    direction=-1 表示转移负向单位，例如冷或黏塑性。
    """
    if source is target:
        raise ValueError("源物品和目标物品不能相同")
    if direction not in (-1, 1):
        raise ValueError("direction 必须是 -1 或 +1")

    next_source = source.get(axis) - direction
    next_target = target.get(axis) + direction
    _validate_value(next_source)
    _validate_value(next_target)

    source.set(axis, next_source)
    target.set(axis, next_target)
    reconcile_processes(source)
    reconcile_processes(target)
