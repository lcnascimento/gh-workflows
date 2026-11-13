import unittest

from fixture import add


class AddTest(unittest.TestCase):
    def test_add_sums_two_numbers(self) -> None:
        self.assertEqual(add(2, 3), 5)


if __name__ == "__main__":
    unittest.main()
