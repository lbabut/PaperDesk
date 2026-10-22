import unittest
from tablet_books_trace import latest

class BooksTraceTests(unittest.TestCase):
    def test_last_observation_discards_stale_geometry_and_disabled_targets(self):
        state, targets = latest('PaperBooks state {"view":"shelf"}\n'
            'PaperBooks target booksOld 100 200 true\n'
            '\x1b[32mPaperBooks state {"view":"search","searchScroll":769}\x1b[0m (handler qrc:/main.qml:20)\n'
            'PaperBooks target booksCurrent 300 400 true\n'
            'PaperBooks target booksDisabled 500 600 false\n')
        self.assertEqual(state['searchScroll'], 769)
        self.assertEqual(targets, {'booksCurrent':(300,400)})

    def test_missing_state_fails_closed(self):
        with self.assertRaises(ValueError): latest('PaperBooks target booksOld 100 200 true\n')

if __name__ == '__main__': unittest.main()
