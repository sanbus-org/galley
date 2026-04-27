from data_structures import VariableSymbol
from glr._data_structures import Item, State
from glr._firsts import GLRParserGeneratorFirstsMixin


class GLRParserGeneratorClosureMixin(GLRParserGeneratorFirstsMixin):
    _closure_cache: dict[State, State]

    def __init__(self) -> None:
        self._closure_cache = {}
        super().__init__()

    # @override
    # def log_to_file(self, directory: Path) -> None:
    #     super().log_to_file(directory)
    # with (directory / "closure.log").open("w") as output:
    #     for variable in self.rules:
    #         print(variable.decode("utf-8"), file=output)
    # print(
    #     "  "
    #     + "\n  ".join(
    #         [
    #             f'"{i.decode("utf-8")}"'
    #             for i in sorted(
    #                 self._closure(VariableSymbol(variable)),
    #             )
    #         ]
    #     ),
    #     file=output,
    # )

    def _closure(self, state: State) -> State:
        if state not in self._closure_cache:
            to_check_items = state.items.copy()
            closure = state.items.copy()
            while to_check_items:
                item = to_check_items.pop()
                if not isinstance(item.head_symbol, VariableSymbol):
                    continue
                for right_hand_side in self.rules[item.head_symbol.id]:
                    firsts = self._firsts([*item.remaining, item.look_ahead])
                    new_items = {
                        Item(
                            variable=item.head_symbol,
                            right_hand_side=right_hand_side,
                            head=0,
                            look_ahead=first,
                        )
                        for first in firsts
                    }
                    to_check_items |= new_items - closure
                    closure |= new_items

            self._closure_cache[state] = State(items=closure)
        return self._closure_cache[state]
