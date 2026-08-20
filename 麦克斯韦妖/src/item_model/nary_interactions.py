from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .model import Axis, Item, Process
from .pair_interactions import AxisRequirement, ProcessRequirement


class ContactMode(str, Enum):
    CONNECTED = "connected"
    ALL_TOUCHING = "all_touching"


@dataclass(frozen=True)
class MemberRequirement:
    """组合技中的一个物品槽位；多个槽位可以要求同一种 kind。"""

    kind: str | None = None
    axes: tuple[AxisRequirement, ...] = ()
    processes: tuple[ProcessRequirement, ...] = ()

    def matches(self, item: Item) -> bool:
        if self.kind is not None and item.kind != self.kind:
            return False
        if any(item.get(req.axis) != req.value for req in self.axes):
            return False
        return all(
            (req.process in item.processes) == req.present
            for req in self.processes
        )


@dataclass(frozen=True)
class ContactGroup:
    """物理系统输出的一个同时接触物品组。

    touching_pairs 使用物品在 items 中的下标，例如 (0, 1)。
    CONNECTED 允许链式接触；ALL_TOUCHING 要求组内每一对都直接接触。
    """

    items: tuple[Item, ...]
    touching_pairs: frozenset[tuple[int, int]] = frozenset()

    def __post_init__(self) -> None:
        if len(self.items) < 2:
            raise ValueError("组合技至少需要两个物品")
        item_count = len(self.items)
        normalized: set[tuple[int, int]] = set()
        for left, right in self.touching_pairs:
            if left == right or not (0 <= left < item_count) or not (0 <= right < item_count):
                raise ValueError("接触对必须是两个不同且存在的物品下标")
            normalized.add((min(left, right), max(left, right)))
        object.__setattr__(self, "touching_pairs", frozenset(normalized))

    def satisfies(self, mode: ContactMode) -> bool:
        if mode is ContactMode.ALL_TOUCHING:
            return all(
                (left, right) in self.touching_pairs
                for left in range(len(self.items))
                for right in range(left + 1, len(self.items))
            )

        visited = {0}
        while True:
            reached = {
                other
                for left, right in self.touching_pairs
                for other in (
                    [right] if left in visited else [left] if right in visited else []
                )
            }
            new_items = reached - visited
            if not new_items:
                return len(visited) == len(self.items)
            visited.update(new_items)


@dataclass(frozen=True)
class CombinationRule:
    rule_id: str
    members: tuple[MemberRequirement, ...]
    event: str
    contact_mode: ContactMode = ContactMode.CONNECTED
    priority: int = 0

    def __post_init__(self) -> None:
        if len(self.members) < 2:
            raise ValueError("组合技至少需要两个成员槽位")

    def matches(self, group: ContactGroup) -> bool:
        if len(group.items) != len(self.members):
            return False
        if not group.satisfies(self.contact_mode):
            return False

        # 组合技无左右顺序。回溯匹配同时支持重复 kind，例如“两块金属+一块水”。
        used: set[int] = set()

        def match_slot(slot: int) -> bool:
            if slot == len(self.members):
                return True
            requirement = self.members[slot]
            for item_index, item in enumerate(group.items):
                if item_index in used or not requirement.matches(item):
                    continue
                used.add(item_index)
                if match_slot(slot + 1):
                    return True
                used.remove(item_index)
            return False

        return match_slot(0)


@dataclass
class CombinationRegistry:
    rules: list[CombinationRule] = field(default_factory=list)

    def register(self, rule: CombinationRule) -> None:
        if any(existing.rule_id == rule.rule_id for existing in self.rules):
            raise ValueError(f"重复的组合技规则: {rule.rule_id}")
        self.rules.append(rule)

    def resolve(self, group: ContactGroup) -> tuple[str, ...]:
        """返回按优先级排序的组合事件；事件执行器负责实际状态修改。"""
        matched = (
            rule for rule in self.rules if rule.matches(group)
        )
        return tuple(rule.event for rule in sorted(
            matched,
            key=lambda rule: (-rule.priority, rule.rule_id),
        ))
