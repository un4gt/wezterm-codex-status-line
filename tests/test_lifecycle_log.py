from __future__ import annotations

import unittest

from scripts.analyze_lifecycle_log import analyze_lines, latest_load_segment


class LifecycleLogTests(unittest.TestCase):
    def test_two_owners_and_tab_move_are_independent(self) -> None:
        result = analyze_lines([
            "10:00:00.000 codex_statusline: update w=0 tab_id=0 pane_id=1 active=true tree=true reason=nil owner_id=1 lifecycle=running generation=a",
            "10:00:00.100 codex_statusline: created status pane id=3 w=0 tab_id=0 owner_id=1 generation=x",
            "10:00:00.200 codex_statusline: update w=0 tab_id=0 pane_id=2 active=true tree=true reason=nil owner_id=2 lifecycle=running generation=b",
            "10:00:00.300 codex_statusline: created status pane id=4 w=0 tab_id=0 owner_id=2 generation=y",
            "10:00:01.000 codex_statusline: requesting exact status pane close id=3 w=0 tab_id=0 reason=owner-moved owner_id=1 generation=x",
            "10:00:01.500 codex_statusline: update w=0 tab_id=1 pane_id=1 active=true tree=true reason=nil owner_id=1 lifecycle=running generation=a",
            "10:00:02.000 codex_statusline: status pane close completed id=3 owner_id=1",
            "10:00:03.000 codex_statusline: created status pane id=5 w=0 tab_id=1 owner_id=1 generation=z",
            "10:00:04.000 codex_statusline: status pane close completed id=3 owner_id=1",
        ])
        self.assertEqual(result["sessions"], 2)
        self.assertEqual(result["warnings"], [])

    def test_unknown_deferred_and_hidden_are_not_failed_recreation(self) -> None:
        result = analyze_lines([
            "10:00:00.000 codex_statusline: update w=0 tab_id=0 pane_id=1 active=true tree=true reason=nil owner_id=1 lifecycle=running generation=a",
            "10:00:01.000 codex_statusline: created status pane id=2 w=0 tab_id=0 owner_id=1 generation=x",
            "10:00:02.000 codex_statusline: update w=0 tab_id=0 pane_id=1 active=true tree=nil reason=unavailable owner_id=1 lifecycle=unknown generation=a",
            "10:00:20.000 codex_statusline: layout deferred owner_id=1 reason=preserve-user-layout",
            "10:00:21.000 codex_statusline: layout deferred owner_id=1 reason=user-hidden",
            "10:00:22.000 codex_statusline: created status pane id=3 w=0 tab_id=0 owner_id=1 generation=y",
        ])
        self.assertEqual(result["sessions"], 1)
        self.assertEqual(result["warnings"], [])

    def test_timeout_and_overlap_have_explicit_diagnostics(self) -> None:
        result = analyze_lines([
            "10:00:00.000 codex_statusline: created status pane id=2 w=0 tab_id=0 owner_id=1 generation=x",
            "10:00:01.000 codex_statusline: requesting exact status pane close id=2 w=0 tab_id=0 reason=inactive owner_id=1 generation=x",
            "10:00:02.000 codex_statusline: update w=0 tab_id=0 pane_id=1 active=true tree=true reason=nil owner_id=1 lifecycle=running generation=b",
            "10:00:11.000 codex_statusline: status pane close timed out id=2 owner_id=1",
            "10:00:12.000 codex_statusline: created status pane id=3 w=0 tab_id=0 owner_id=1 generation=y",
        ])
        self.assertEqual({item["code"] for item in result["warnings"]}, {"CLOSE_TIMEOUT", "OVERLAPPING_STATUS_GENERATIONS"})

    def test_detects_slow_exit_and_missing_restart_pane(self) -> None:
        result = analyze_lines(
            [
                "23:55:45.148 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=codex.exe active=true tree=true codex_pid=2000 kind=native reason=nil title_bridge=nil\n",
                "23:55:45.366 lua: codex_statusline: created status pane id=1 w=0 tab_id=0 key=0:0 size=1 rows(status/main)=1/50\n",
                "23:58:26.570 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=oh-my-posh.exe active=true tree=nil codex_pid=nil kind=nil reason=terminal-boundary title_bridge=nil\n",
                "23:58:31.507 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=pwsh.exe active=false tree=nil codex_pid=nil kind=nil reason=terminal-boundary title_bridge=nil\n",
                "23:58:33.242 lua: codex_statusline: requesting exact status pane close id=1 w=0 tab_id=0 reason=inactive\n",
                "23:59:18.829 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=git.exe active=true tree=true codex_pid=8864 kind=native reason=nil title_bridge=terminal-title\n",
                "23:59:18.829 lua: codex_statusline: unable to verify status pane id=1\n",
                "23:59:19.004 lua: codex_statusline: unable to verify status pane id=1\n",
                "23:59:19.313 lua: codex_statusline: unable to verify status pane id=1\n",
            ]
        )
        codes = {item["code"] for item in result["warnings"]}
        self.assertEqual(result["sessions"], 2)
        self.assertIn("SLOW_EXIT", codes)
        self.assertIn("STATUS_NOT_RECREATED", codes)
        self.assertIn("STALE_PANE_LOOKUP_LOOP", codes)

    def test_clean_exit_and_restart_have_no_warning(self) -> None:
        result = analyze_lines(
            [
                "10:00:00.000 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=codex.exe active=true tree=true codex_pid=100 kind=native reason=nil\n",
                "10:00:00.100 lua: codex_statusline: created status pane id=1 w=0 tab_id=0 key=0:0\n",
                "10:01:00.000 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=pwsh.exe active=false tree=false codex_pid=nil kind=nil reason=terminal-boundary\n",
                "10:01:02.000 lua: codex_statusline: requesting exact status pane close id=1 w=0 tab_id=0 reason=inactive\n",
                "10:01:03.000 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=codex.exe active=true tree=true codex_pid=200 kind=native reason=nil\n",
                "10:01:03.100 lua: codex_statusline: created status pane id=2 w=0 tab_id=0 key=0:0\n",
            ]
        )
        self.assertEqual(result["sessions"], 2)
        self.assertEqual(result["warnings"], [])

    def test_clock_rollover_stays_monotonic(self) -> None:
        result = analyze_lines(
            [
                "23:59:58.000 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=codex.exe active=true tree=true codex_pid=100 kind=native reason=nil\n",
                "23:59:58.100 lua: codex_statusline: created status pane id=1 w=0 tab_id=0 key=0:0\n",
                "23:59:59.000 lua: codex_statusline: update w=0 tab_id=0 pane_id=0 fg=pwsh.exe active=false tree=false codex_pid=nil kind=nil reason=terminal-boundary\n",
                "00:00:01.000 lua: codex_statusline: requesting exact status pane close id=1 w=0 tab_id=0 reason=inactive\n",
            ]
        )
        self.assertEqual(result["warnings"], [])

    def test_latest_load_segment_discards_historical_failures(self) -> None:
        lines, start_line = latest_load_segment(
            [
                "10:00:00.000 old lifecycle warning\n",
                "10:01:00.000 lua: codex_statusline: CODEX_STATUSLINE_LOADED module_id=old\n",
                "10:02:00.000 old generation event\n",
                "10:03:00.000 lua: codex_statusline: CODEX_STATUSLINE_LOADED module_id=new\n",
                "10:04:00.000 new generation event\n",
            ]
        )
        self.assertEqual(start_line, 4)
        self.assertEqual(len(lines), 2)
        self.assertIn("module_id=new", lines[0])


if __name__ == "__main__":
    unittest.main()
