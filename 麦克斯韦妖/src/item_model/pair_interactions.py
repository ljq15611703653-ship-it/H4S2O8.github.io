from __future__ import annotations

from dataclasses import dataclass, field

from .model import Axis, Item, Process


@dataclass(frozen=True)
class AxisRequirement:
    axis: Axis
    value: int


@dataclass(frozen=True)
class ProcessRequirement:
    process: Process
    present: bool = True


@dataclass(frozen=True)
class PairRule:
    rule_id: str
    left_kind: str | None
    right_kind: str | None
    event: str
    left_axes: tuple[AxisRequirement, ...] = ()
    right_axes: tuple[AxisRequirement, ...] = ()
    left_processes: tuple[ProcessRequirement, ...] = ()
    right_processes: tuple[ProcessRequirement, ...] = ()
    symmetric: bool = False

    @staticmethod
    def _matches_side(
        item: Item,
        kind: str | None,
        axes: tuple[AxisRequirement, ...],
        processes: tuple[ProcessRequirement, ...],
    ) -> bool:
        if kind is not None and item.kind != kind:
            return False
        if any(item.get(req.axis) != req.value for req in axes):
            return False
        return all(
            (req.process in item.processes) == req.present
            for req in processes
        )

    def _matches_direct(self, left: Item, right: Item) -> bool:
        return self._matches_side(
            left, self.left_kind, self.left_axes, self.left_processes
        ) and self._matches_side(
            right, self.right_kind, self.right_axes, self.right_processes
        )

    def matches(self, left: Item, right: Item) -> bool:
        return self._matches_direct(left, right) or (
            self.symmetric and self._matches_direct(right, left)
        )


@dataclass
class InteractionRegistry:
    rules: list[PairRule] = field(default_factory=list)

    def register(self, rule: PairRule) -> None:
        if any(existing.rule_id == rule.rule_id for existing in self.rules):
            raise ValueError(f"重复的物品交互规则: {rule.rule_id}")
        self.rules.append(rule)

    def resolve(self, left: Item, right: Item) -> tuple[str, ...]:
        """返回当前物品对触发的事件；实际状态修改由事件执行器负责。"""
        return tuple(rule.event for rule in self.rules if rule.matches(left, right))
