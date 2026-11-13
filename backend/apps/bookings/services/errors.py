class BookingError(Exception):
    """A rule was broken. `code` is mapped to a status and a French message by the callers."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code
