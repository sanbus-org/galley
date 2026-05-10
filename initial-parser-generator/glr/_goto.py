from collections import defaultdict
from functools import cached_property
from pathlib import Path
from typing import override

from data_structures import EndSymbol, Symbol
from glr._closure import GLRParserGeneratorClosureMixin
from glr._data_structures import Item, State, empty_state


class GLRParserGeneratorGotoMixin(GLRParserGeneratorClosureMixin):
    _goto_cache: dict[State, dict[int, State]]

    def __init__(self) -> None:
        self._goto_cache = defaultdict(dict)
        super().__init__()

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        with (directory / "states.log").open("w") as output:
            for index, state in enumerate(self.canonical_states):
                print(f"{index}.", state, file=output)

    @cached_property
    def canonical_states(self) -> list[State]:
        initial_state = self._closure(
            State(
                items=frozenset(
                    {
                        Item(
                            variable=self.start_variable,
                            right_hand_side=self.rules[self.start_variable.id][0],
                            head=0,
                            look_ahead=EndSymbol(),
                        )
                    }
                )
            )
        )
        collection: list[State] = [initial_state]
        hashes: list[int] = [hash(initial_state)]
        queue: list[State] = [initial_state]

        def report_progress():
            print(f"Collection size: {len(collection)}, Queue length: {len(queue)}")

        progress_step = 1000

        last_size_report = -1
        report_progress()
        while len(queue) > 0:
            if (size := len(collection)) - last_size_report > progress_step:
                report_progress()
                last_size_report = (size // progress_step) * progress_step
            state = queue.pop(0)
            for symbol in self.symbols:
                to_add = self._goto(state, symbol)
                if hash(to_add) not in hashes:
                    collection.append(to_add)
                    hashes.append(hash(to_add))
                    queue.append(to_add)

        report_progress()

        return collection

    @cached_property
    def canonical_state_indices(self) -> dict[State, int]:
        return {state: index for index, state in enumerate(self.canonical_states)}

    def _goto(self, state: State, symbol: Symbol) -> State:
        if symbol.index not in self._goto_cache[state]:
            if symbol.index not in state.items_by_symbol:
                return empty_state
            self._goto_cache[state][symbol.index] = self._closure(
                state.items_by_symbol[symbol.index],
            )
        return self._goto_cache[state][symbol.index]
