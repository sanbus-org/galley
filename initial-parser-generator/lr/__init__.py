from glr import GLRParserGenerator
from lr._zig import LRParserGeneratorZigMixin


class LRParserGenerator(LRParserGeneratorZigMixin, GLRParserGenerator):
    parser_type = "lr"
