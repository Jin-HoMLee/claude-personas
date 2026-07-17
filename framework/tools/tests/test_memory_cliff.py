import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr

# Import the module under test from the parent framework/tools/ dir.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import memory_cliff as mc  # noqa: E402

# The template's canonical tier-1 header (see CONVENTIONS.md). The counter must
# detect this form, not just the bare "## Always in effect" the source instance used.
# The live files use an em-dash (U+2014); TIER1_EMDASH mirrors the on-disk format
# exactly so at least one test exercises the real bytes (the matcher only keys on
# "Always", so both forms must work).
TIER1 = "## Tier 1 - Always in effect"
TIER1_EMDASH = "## Tier 1 — Always in effect"
TEMPLATE_ROLES = ("pm", "scientist", "developer", "designer")


class _CorpusBuilderMixin:
    """Shared test helpers for building corpus structures."""
    def _write(self, root, rel, content):
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    def _flat_index(self, root, content):
        """Write the single flat-layout index file (Task 9)."""
        self._write(root, mc.FLAT_INDEX_REL, content)

    def _manifest(self, root, memory_layout, extra=""):
        """Write a minimal `.agents/manifest` declaring `memory_layout` (Task 9).
        `extra` lets a test add stray lines (comments/blanks/unrelated keys)."""
        self._write(
            root, os.path.join(".agents", "manifest"),
            f"manifest_version=1\nmemory_layout={memory_layout}\n{extra}",
        )

    def _role(self, root, r, content):
        """Write a role's MEMORY.md AND its `shared` symlink, so discover() finds it."""
        self._write(root, f"{r}/MEMORY.md", content)
        link = os.path.join(root, r, "shared")
        if not os.path.islink(link):
            os.symlink("../shared", link)

    def _corpus(self, root, shared_rules, role_rules, header=TIER1):
        self._write(
            root, "shared/MEMORY.md",
            header + "\n" + "".join(f"- **S{i}:** x\n" for i in range(shared_rules)),
        )
        for r in TEMPLATE_ROLES:
            self._role(
                root, r,
                header + "\n" + "".join(f"- **{r}{i}:** x\n" for i in range(role_rules)),
            )


class TestApproxTokens(unittest.TestCase):
    def test_floor_division_by_four(self):
        self.assertEqual(mc.approx_tokens(""), 0)
        self.assertEqual(mc.approx_tokens("abc"), 0)        # 3 // 4
        self.assertEqual(mc.approx_tokens("abcd"), 1)       # 4 // 4
        self.assertEqual(mc.approx_tokens("abcdefgh"), 2)   # 8 // 4


class TestExtractSection(unittest.TestCase):
    def test_template_tier1_header_matched(self):
        # The template's "## Tier 1 - Always in effect" must be detected even though
        # it does not START with "Always".
        text = TIER1 + "\n- **A:** x\n- **B:** y\n"
        sec = mc.extract_section(text)
        self.assertEqual(sec[0], TIER1)
        self.assertEqual(mc.count_rules(sec), 2)

    def test_template_tier1_header_emdash_matched(self):
        # The on-disk files use an em-dash; it must parse identically to the hyphen.
        text = TIER1_EMDASH + "\n- **A:** x\n- **B:** y\n"
        sec = mc.extract_section(text)
        self.assertEqual(sec[0], TIER1_EMDASH)
        self.assertEqual(mc.count_rules(sec), 2)

    def test_compound_noun_always_header_not_captured(self):
        # A prose/compound-noun header that merely MENTIONS "Always" (hyphenated, not
        # a space-separated section header) must not be treated as an always-section.
        for header in (
            "## Notes on Always-in-effect rules",
            "## Overview of Always-loaded memory",
            "## Why Always-loaded rules matter",
        ):
            with self.subTest(header=header):
                self.assertEqual(mc.extract_section(header + "\n- **A:** x\n"), [])

    def test_fenced_bullet_not_counted(self):
        # A rule-format example shown inside a fenced code block is not a live rule.
        text = (
            TIER1 + "\nExample usage:\n"
            "```\n- **Not a rule:** just an example\n```\n"
            "- **Actual rule:** do X.\n"
        )
        sec = mc.extract_section(text)
        self.assertEqual(mc.count_rules(sec), 1)

    def test_tilde_fence_not_closed_by_backtick_fence(self):
        # A ~~~ fence is only closed by ~~~ (not by ```), so its content stays dropped.
        text = (
            TIER1 + "\n"
            "~~~\n- **In tilde fence:** x\n```\n- **Still in fence:** y\n~~~\n"
            "- **Live:** z\n"
        )
        self.assertEqual(mc.count_rules(mc.extract_section(text)), 1)

    def test_header_with_suffix_to_eof(self):
        text = (
            "# Title\n\n"
            "## Always in effect (no file read required)\n\n"
            "- **A:** x\n- **B:** y\n"
        )
        sec = mc.extract_section(text)
        self.assertEqual(sec[0], "## Always in effect (no file read required)")
        self.assertIn("- **A:** x", sec)
        self.assertIn("- **B:** y", sec)

    def test_terminated_by_sibling_heading(self):
        text = TIER1 + "\n- **A:** x\n## Tier 2 - Reference\n- **Z:** skip\n"
        self.assertEqual(mc.extract_section(text), [TIER1, "- **A:** x"])

    def test_role_index_section_not_captured(self):
        # The template's "## Shared (all sessions)" / "## Role: PM" index sections
        # carry link bullets, not always-loaded rules, and must be excluded.
        text = (
            TIER1 + "\n- **A:** x\n"
            "## Shared (all sessions)\n- [Shared index](shared/MEMORY.md) - x\n"
            "## Role: PM\n- [Check board](feedback_check_board.md) - y\n"
        )
        sec = mc.extract_section(text)
        self.assertEqual(mc.count_rules(sec), 1)
        self.assertNotIn("- [Shared index](shared/MEMORY.md) - x", sec)

    def test_absent_section_returns_empty(self):
        self.assertEqual(mc.extract_section("# Title\nno section here\n"), [])

    def test_sibling_always_sections_included(self):
        text = (
            TIER1 + "\n- **A:** x\n"
            "## Always run at session start\n- **B:** y\n"
            "## Tier 2 - Reference\n- **Z:** skip\n"
        )
        sec = mc.extract_section(text)
        self.assertIn("- **A:** x", sec)
        self.assertIn("- **B:** y", sec)        # sibling always-section counted
        self.assertNotIn("- **Z:** skip", sec)  # lazy Reference section excluded
        self.assertEqual(mc.count_rules(sec), 2)

    # --- header word-boundary ---
    def test_alwaysish_glued_header_not_matched(self):
        # "## Alwaysish" has no word boundary after "Always" -> not an always-section.
        self.assertEqual(mc.extract_section("## Alwaysish notes\n- **A:** x\n"), [])

    # --- heading / indentation edges ---
    def test_h3_subheading_kept_then_h2_terminates(self):
        text = TIER1 + "\n- **A:** x\n### Sub\n- **B:** y\n## Next\n- **C:** z\n"
        sec = mc.extract_section(text)
        self.assertIn("### Sub", sec)            # h3 does not terminate
        self.assertIn("- **B:** y", sec)
        self.assertNotIn("- **C:** z", sec)      # past the next h2
        self.assertEqual(mc.count_rules(sec), 2)

    def test_indented_header_is_not_a_section(self):
        self.assertEqual(mc.extract_section("  " + TIER1 + "\n- **A:** x\n"), [])

    # --- CRLF ---
    def test_crlf_parses_like_lf(self):
        lf = TIER1 + "\n- **A:** x\n- **B:** y\n"
        crlf = lf.replace("\n", "\r\n")
        self.assertEqual(mc.analyze_text(crlf).rules, mc.analyze_text(lf).rules)
        sec = mc.extract_section(crlf)
        self.assertTrue(all(not line.endswith("\r") for line in sec))


class TestCountRules(unittest.TestCase):
    def test_counts_top_level_bold_bullets_only(self):
        section = [
            TIER1,
            "- **Rule one:** text",
            "  - **nested:** not a rule",       # space-indented sub-bullet
            "\t- **tabbed:** not a rule",        # tab-indented sub-bullet
            "- plain bullet, not a rule",
            "- **Rule two:** text",
            "Some **bold** mid-line, not a bullet",
        ]
        self.assertEqual(mc.count_rules(section), 2)

    def test_commented_example_bullet_not_counted(self):
        # The pristine template ships an example rule INSIDE an HTML comment; it must
        # not count as a live rule.
        section = [
            TIER1,
            "<!-- Add inline rules here. Example:",
            "- **My rule:** Description. <!-- src: shared/feedback_my_rule.md -->",
            "-->",
        ]
        self.assertEqual(mc.count_rules(section), 0)

    def test_real_rule_with_inline_annotation_still_counted(self):
        # A live rule that carries a trailing drift-annotation comment still counts.
        section = [
            TIER1,
            "- **My rule:** Don't do X. <!-- src: shared/feedback_my_rule.md -->",
        ]
        self.assertEqual(mc.count_rules(section), 1)


class TestAnalyzeText(unittest.TestCase):
    def test_known_counts(self):
        text = TIER1 + "\n- **A:** x\n- **B:** y\n"
        m = mc.analyze_text(text)
        self.assertEqual(m.rules, 2)
        self.assertEqual(m.always_lines, 3)     # header + 2 bullets
        self.assertEqual(m.file_lines, 3)
        expected = len(TIER1 + "\n- **A:** x\n- **B:** y") // 4
        self.assertEqual(m.tokens, expected)

    def test_commented_example_counts_lines_not_rules(self):
        # Comments still load into context (lines/tokens count), but a commented-out
        # example bullet is not a live rule (rules == 0). Mirrors the pristine template.
        text = (
            TIER1 + "\n\n"
            "<!-- Add inline rules here. Example:\n"
            "- **My rule:** Description. <!-- src: shared/feedback_my_rule.md -->\n"
            "-->\n"
        )
        m = mc.analyze_text(text)
        self.assertEqual(m.rules, 0)
        self.assertGreater(m.always_lines, 1)   # comment lines still counted for the line budget

    def test_absent_section_zeros(self):
        m = mc.analyze_text("# Title\nbody only\n")
        self.assertEqual(m.rules, 0)
        self.assertEqual(m.always_lines, 0)
        self.assertEqual(m.tokens, 0)
        self.assertEqual(m.file_lines, 2)

    # --- file_lines == wc -l, incl. no trailing newline ---
    def test_file_lines_counts_newlines(self):
        self.assertEqual(mc.analyze_text("a\nb\nc\n").file_lines, 3)
        self.assertEqual(mc.analyze_text("a\nb\nc").file_lines, 2)   # wc -l semantics


class TestEffectiveLoad(unittest.TestCase):
    def test_sums_role_and_shared(self):
        role = mc.FileMetrics(rules=5, always_lines=10, file_lines=20, tokens=100)
        shared = mc.FileMetrics(rules=30, always_lines=31, file_lines=121, tokens=2000)
        load = mc.effective_load("pm", role, shared)
        self.assertEqual(load.role, "pm")
        self.assertEqual(load.rules, 35)
        self.assertEqual(load.always_lines, 41)
        self.assertEqual(load.tokens, 2100)


class TestClassify(unittest.TestCase):
    def test_at_threshold_is_ok(self):
        load = mc.RoleLoad("pm", rules=14, always_lines=200, tokens=4000)
        self.assertEqual(mc.classify(load), [])

    def test_over_rules_only(self):
        load = mc.RoleLoad("pm", rules=15, always_lines=50, tokens=1000)
        self.assertEqual(mc.classify(load), ["rules"])

    def test_over_tokens_only(self):
        load = mc.RoleLoad("pm", rules=10, always_lines=50, tokens=4001)
        self.assertEqual(mc.classify(load), ["tokens"])

    def test_over_lines_only(self):
        load = mc.RoleLoad("pm", rules=10, always_lines=201, tokens=1000)
        self.assertEqual(mc.classify(load), ["lines"])

    def test_over_multiple_axes_ordered(self):
        load = mc.RoleLoad("pm", rules=15, always_lines=201, tokens=4001)
        self.assertEqual(mc.classify(load), ["rules", "lines", "tokens"])


class TestAnalyzeFile(unittest.TestCase):
    def test_missing_file_returns_none(self):
        self.assertIsNone(mc.analyze_file("/no/such/MEMORY.md"))

    def test_reads_existing_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "MEMORY.md")
            with open(p, "w", encoding="utf-8") as f:
                f.write(TIER1 + "\n- **A:** x\n")
            m = mc.analyze_file(p)
            self.assertEqual(m.rules, 1)

    # --- BOM must not hide the header ---
    def test_leading_bom_does_not_zero_metrics(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "MEMORY.md")
            with open(p, "w", encoding="utf-8-sig") as f:   # writes a leading BOM
                f.write(TIER1 + "\n- **A:** x\n- **B:** y\n")
            m = mc.analyze_file(p)
            self.assertEqual(m.rules, 2)


class TestDiscover(_CorpusBuilderMixin, unittest.TestCase):
    def test_discovers_template_roles_and_shared(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=1, role_rules=1)
            corpus = mc.discover(root)
            self.assertEqual(corpus.shared_dir, "shared")
            self.assertEqual(set(corpus.role_dirs), set(TEMPLATE_ROLES))

    def test_shared_dir_is_not_a_role(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=1, role_rules=1)
            # shared/ has a MEMORY.md but no `shared` symlink -> not a role dir.
            self.assertNotIn("shared", mc.discover(root).role_dirs)


class TestRender(unittest.TestCase):
    def test_contains_rows_and_status(self):
        per_file = [
            ("shared", mc.FileMetrics(rules=13, always_lines=20, file_lines=40, tokens=800)),
            ("pm", mc.FileMetrics(rules=5, always_lines=10, file_lines=25, tokens=300)),
            ("scientist", None),
        ]
        per_role = [
            mc.RoleLoad("pm", rules=18, always_lines=30, tokens=1100),        # OVER rules
            mc.RoleLoad("scientist", rules=13, always_lines=20, tokens=800),  # OK
        ]
        out = mc.render(per_file, per_role)
        self.assertIn("shared", out)
        self.assertIn("(missing", out)             # missing file noted, not crashed
        self.assertIn("OVER (rules)", out)
        self.assertIn("OK", out)
        self.assertIn("Thresholds:", out)
        self.assertIn("Reference", out)   # footer notes the lazy Reference section is excluded

    def test_role_table_exposes_lines_axis(self):
        # A lines-only breach must show a visible AlwaysLines number, not an
        # invisible axis behind 'OVER (lines)'.
        per_role = [mc.RoleLoad("pm", rules=10, always_lines=250, tokens=900)]
        out = mc.render([("shared", None)], per_role)
        self.assertIn("AlwaysLines", out)          # column header present
        self.assertIn("250", out)                  # the breaching number is visible
        self.assertIn("OVER (lines)", out)


class TestMainIntegration(_CorpusBuilderMixin, unittest.TestCase):
    def _run(self, root):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = mc.main(["--root", root])
        return rc, buf.getvalue()

    def test_exit_1_and_over_when_breaching(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=13, role_rules=5)   # effective 18 > 14
            rc, out = self._run(root)
            self.assertEqual(rc, 1)
            self.assertIn("OVER", out)

    def test_exit_0_and_ok_when_under(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)    # effective 4 < 14
            rc, out = self._run(root)
            self.assertEqual(rc, 0)
            self.assertIn("OK", out)

    # --- lines-only breach end-to-end ---
    def test_exit_1_via_lines_axis_only(self):
        with tempfile.TemporaryDirectory() as root:
            self._write(root, "shared/MEMORY.md", TIER1 + "\n- **S0:** x\n")
            # 13 rules + 190 trailing blank lines; no '## ' heading terminates them, so all
            # 190 stay inside the section -> effective rules 14 (OK), effective lines >200 (OVER)
            body = "".join(f"- **P{i}:** x\n" for i in range(13)) + ("\n" * 190)
            self._role(root, "pm", TIER1 + "\n" + body)
            for r in ("scientist", "developer", "designer"):
                self._role(root, r, TIER1 + "\n- **One:** x\n")
            rc, out = self._run(root)
            self.assertEqual(rc, 1)
            self.assertIn("OVER (lines)", out)

    # --- tokens-only breach end-to-end ---
    def test_exit_1_via_tokens_axis_only(self):
        with tempfile.TemporaryDirectory() as root:
            self._write(root, "shared/MEMORY.md", TIER1 + "\n- **S0:** x\n")
            big = "- **P0:** " + ("x" * 17000) + "\n"   # 1 rule, ~4250 tokens
            self._role(root, "pm", TIER1 + "\n" + big)
            for r in ("scientist", "developer", "designer"):
                self._role(root, r, TIER1 + "\n- **One:** x\n")
            rc, out = self._run(root)
            self.assertEqual(rc, 1)
            self.assertIn("OVER (tokens)", out)

    # --- discovery-appropriate missing-file tests ---
    def test_role_dir_without_memory_md_not_discovered(self):
        with tempfile.TemporaryDirectory() as root:
            self._write(root, "shared/MEMORY.md", TIER1 + "\n- **S:** x\n")
            for r in ("pm", "scientist", "developer"):
                self._role(root, r, TIER1 + "\n- **One:** x\n")
            # designer: symlink only, no MEMORY.md -> not a role
            os.makedirs(os.path.join(root, "designer"), exist_ok=True)
            os.symlink("../shared", os.path.join(root, "designer", "shared"))
            rc, out = self._run(root)
            self.assertNotIn("designer", out)   # not discovered -> no row
            self.assertEqual(rc, 0)             # present roles under cliff

    def test_missing_shared_rendered_not_crashed(self):
        with tempfile.TemporaryDirectory() as root:
            # no shared/MEMORY.md at all
            for r in ("pm", "scientist"):
                self._role(root, r, TIER1 + "\n- **One:** x\n")
            rc, out = self._run(root)
            self.assertIn("(missing", out)            # shared row shown as missing
            self.assertEqual(rc, 0)

    # --- unreadable/corrupt file -> clean exit 2 ---
    def test_exit_2_on_invalid_utf8(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)
            with open(os.path.join(root, "pm/MEMORY.md"), "wb") as f:
                # b"\xff\xfe" is a UTF-16 LE BOM; \xff is invalid UTF-8, so the
                # utf-8-sig read raises UnicodeDecodeError (-> caught -> exit 2).
                f.write(b"\xff\xfe## Tier 1 - Always in effect\n- **A:** x\n")
            buf, err = io.StringIO(), io.StringIO()
            with redirect_stdout(buf), redirect_stderr(err):
                rc = mc.main(["--root", root])
            self.assertEqual(rc, 2)
            self.assertIn("error", err.getvalue().lower())

    def test_exit_2_on_unreadable_root(self):
        # discover() -> os.listdir(root) raises FileNotFoundError (OSError) on a
        # nonexistent root; main() maps it to a clean exit 2.
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            rc = mc.main(["--root", os.path.join(os.path.dirname(__file__), "no_such_root_xyz")])
        self.assertEqual(rc, 2)
        self.assertIn("error", err.getvalue().lower())


class TestBaselineUnit(unittest.TestCase):
    def test_write_then_load_roundtrip(self):
        per_role = [mc.RoleLoad("pm", 14, 200, 4000),
                    mc.RoleLoad("scientist", 10, 100, 2000)]
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "b.json")
            mc.write_baseline(p, per_role)
            data = mc.load_baseline(p)
            self.assertEqual(data["pm"], {"rules": 14, "always_lines": 200, "tokens": 4000})
            self.assertEqual(data["scientist"]["rules"], 10)

    def test_compare_equal_is_ok(self):
        per_role = [mc.RoleLoad("pm", 14, 200, 4000)]
        base = {"pm": {"rules": 14, "always_lines": 200, "tokens": 4000}}
        self.assertEqual(mc.compare_to_baseline(per_role, base), [])

    def test_compare_improved_is_ok(self):
        per_role = [mc.RoleLoad("pm", 13, 199, 3999)]
        base = {"pm": {"rules": 14, "always_lines": 200, "tokens": 4000}}
        self.assertEqual(mc.compare_to_baseline(per_role, base), [])

    def test_compare_worsened_axis_flagged(self):
        per_role = [mc.RoleLoad("pm", 15, 200, 4000)]
        base = {"pm": {"rules": 14, "always_lines": 200, "tokens": 4000}}
        regs = mc.compare_to_baseline(per_role, base)
        self.assertEqual(len(regs), 1)
        self.assertIn("rules", regs[0])
        self.assertIn("14->15", regs[0])

    def test_compare_role_absent_from_baseline_flagged(self):
        per_role = [mc.RoleLoad("newrole", 1, 1, 1)]
        self.assertTrue(mc.compare_to_baseline(per_role, {}))

    def test_compare_role_deleted_from_disk_is_silent_pass(self):
        # A role in the baseline but absent from per_role (removed from disk after
        # baselining) is intentionally not a regression - the ratchet bounds growth.
        per_role = [mc.RoleLoad("pm", 14, 200, 4000)]
        base = {
            "pm": {"rules": 14, "always_lines": 200, "tokens": 4000},
            "designer": {"rules": 5, "always_lines": 50, "tokens": 1000},
        }
        self.assertEqual(mc.compare_to_baseline(per_role, base), [])

    def test_load_baseline_missing_raises_oserror(self):
        with self.assertRaises(OSError):
            mc.load_baseline("/no/such/baseline.json")

    def test_load_baseline_malformed_raises_valueerror(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "b.json")
            with open(p, "w", encoding="utf-8") as f:
                f.write("not json {{{")
            with self.assertRaises(ValueError):
                mc.load_baseline(p)

    def test_load_baseline_non_dict_json_raises_valueerror(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "b.json")
            with open(p, "w", encoding="utf-8") as f:
                f.write("[1, 2, 3]")          # valid JSON, but not a {role: {...}} object
            with self.assertRaises(ValueError):
                mc.load_baseline(p)


class TestBaselineMainIntegration(_CorpusBuilderMixin, unittest.TestCase):
    def test_write_then_baseline_unchanged_passes(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=20, role_rules=5)   # over absolute cliff: ratchet still OK
            bpath = os.path.join(root, "baseline.json")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(mc.main(["--root", root, "--write-baseline", bpath]), 0)
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = mc.main(["--root", root, "--baseline", bpath])
            self.assertEqual(rc, 0)
            self.assertIn("Ratchet OK", buf.getvalue())

    def test_baseline_fails_after_growth(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=20, role_rules=5)
            bpath = os.path.join(root, "baseline.json")
            with redirect_stdout(io.StringIO()):
                mc.main(["--root", root, "--write-baseline", bpath])
            self._write(root, "pm/MEMORY.md",
                        TIER1 + "\n" + "".join(f"- **pm{i}:** x\n" for i in range(6)))
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = mc.main(["--root", root, "--baseline", bpath])
            self.assertEqual(rc, 1)
            self.assertIn("RATCHET FAILED", buf.getvalue())
            self.assertIn("pm", buf.getvalue())

    def test_baseline_missing_file_exits_2(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)
            err = io.StringIO()
            with redirect_stderr(err):
                rc = mc.main(["--root", root, "--baseline", os.path.join(root, "nope.json")])
            self.assertEqual(rc, 2)

    def test_baseline_mode_prints_wholefile_info(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=3, role_rules=3)
            bpath = os.path.join(root, "baseline.json")
            with redirect_stdout(io.StringIO()):
                mc.main(["--root", root, "--write-baseline", bpath])
            buf = io.StringIO()
            with redirect_stdout(buf):
                mc.main(["--root", root, "--baseline", bpath])
            self.assertIn("Whole-file size", buf.getvalue())

    def test_default_mode_unchanged(self):
        # No baseline flag -> absolute-cliff behavior + exit code.
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)   # under cliff
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = mc.main(["--root", root])
            self.assertEqual(rc, 0)
            self.assertIn("OK", buf.getvalue())
            self.assertNotIn("Ratchet", buf.getvalue())

    def test_baseline_fails_on_sibling_always_section_growth(self):
        with tempfile.TemporaryDirectory() as root:
            # shared has TWO always-loaded sections; roles each have one.
            self._write(
                root, "shared/MEMORY.md",
                TIER1 + "\n- **S0:** x\n"
                "## Always run at session start\n- **S1:** y\n",
            )
            for r in TEMPLATE_ROLES:
                self._role(root, r, TIER1 + "\n- **One:** x\n")
            bpath = os.path.join(root, "baseline.json")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(mc.main(["--root", root, "--write-baseline", bpath]), 0)
            # grow the SIBLING (session-start) section by one rule
            self._write(
                root, "shared/MEMORY.md",
                TIER1 + "\n- **S0:** x\n"
                "## Always run at session start\n- **S1:** y\n- **S2:** z\n",
            )
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = mc.main(["--root", root, "--baseline", bpath])
            self.assertEqual(rc, 1)
            self.assertIn("RATCHET FAILED", buf.getvalue())


class TestReadManifestLayout(_CorpusBuilderMixin, unittest.TestCase):
    def test_missing_manifest_returns_none(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(mc.read_manifest_layout(root))

    def test_manifest_without_memory_layout_key_returns_none(self):
        with tempfile.TemporaryDirectory() as root:
            self._write(root, os.path.join(".agents", "manifest"), "manifest_version=1\ntopology=embedded\n")
            self.assertIsNone(mc.read_manifest_layout(root))

    def test_reads_flat(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "flat")
            self.assertEqual(mc.read_manifest_layout(root), "flat")

    def test_reads_roles(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "roles")
            self.assertEqual(mc.read_manifest_layout(root), "roles")

    def test_comments_and_blank_lines_ignored(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "flat", extra="# a comment\n\n   \nadapter=claude-code\n")
            self.assertEqual(mc.read_manifest_layout(root), "flat")

    def test_first_value_wins(self):
        with tempfile.TemporaryDirectory() as root:
            self._write(
                root, os.path.join(".agents", "manifest"),
                "memory_layout=flat\nmemory_layout=roles\n",
            )
            self.assertEqual(mc.read_manifest_layout(root), "flat")

    def test_malformed_manifest_directory_not_file_is_tolerated(self):
        # `.agents/manifest` exists as a directory (unreadable as a file) - the
        # linter must not crash, just treat it as no signal.
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, ".agents", "manifest"))
            self.assertIsNone(mc.read_manifest_layout(root))


class TestResolveLayout(_CorpusBuilderMixin, unittest.TestCase):
    def test_no_flag_no_manifest_defaults_to_roles(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(mc.resolve_layout(None, root), "roles")

    def test_manifest_flat_no_flag(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "flat")
            self.assertEqual(mc.resolve_layout(None, root), "flat")

    def test_flag_overrides_manifest(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "flat")
            self.assertEqual(mc.resolve_layout("roles", root), "roles")

    def test_malformed_manifest_value_falls_back_to_roles(self):
        with tempfile.TemporaryDirectory() as root:
            self._manifest(root, "nonsense")
            self.assertEqual(mc.resolve_layout(None, root), "roles")


class TestAnalyzeTextWholeFile(unittest.TestCase):
    def test_whole_file_is_always_ignores_section_headers(self):
        # No "Always" header at all - roles-style extraction would return zero
        # rules; whole-file mode must still count every top-level bullet.
        text = "# Some Index\n- **A:** x\n- **B:** y\n- **C:** z\n"
        m = mc.analyze_text(text, whole_file_is_always=True)
        self.assertEqual(m.rules, 3)
        # text ends with a trailing "\n" so splitlines() and the `wc -l` newline
        # count agree exactly (no dangling unterminated final line).
        self.assertEqual(m.always_lines, m.file_lines)
        self.assertEqual(m.always_lines, 4)

    def test_default_unaffected(self):
        # Sanity: the new parameter defaults False and reproduces the exact prior
        # roles-style behavior (extract_section, not the whole file).
        text = "# Some Index\n- **A:** x\n"
        m = mc.analyze_text(text)
        self.assertEqual(m.rules, 0)   # no always-section -> nothing counted
        self.assertEqual(m.always_lines, 0)


class TestComputeLoadsFlat(_CorpusBuilderMixin, unittest.TestCase):
    def test_one_index_row_whole_file_counts(self):
        with tempfile.TemporaryDirectory() as root:
            content = "".join(f"- **R{i}:** x\n" for i in range(5))
            self._flat_index(root, content)
            per_file, per_role = mc.compute_loads_flat(root)
            self.assertEqual([name for name, _ in per_file], ["index"])
            self.assertEqual(per_file[0][1].rules, 5)
            self.assertEqual(len(per_role), 1)
            self.assertEqual(per_role[0].role, "index")
            self.assertEqual(per_role[0].rules, 5)

    def test_missing_index_raises_oserror(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(OSError):
                mc.compute_loads_flat(root)


class TestMainFlatLayout(_CorpusBuilderMixin, unittest.TestCase):
    def _run(self, args):
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            rc = mc.main(args)
        return rc, buf.getvalue(), err.getvalue()

    def test_layout_flag_flat_one_index_row_under_cliff(self):
        with tempfile.TemporaryDirectory() as root:
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(3)))
            rc, out, _ = self._run(["--root", root, "--layout", "flat"])
            self.assertEqual(rc, 0)
            self.assertIn("index", out)
            self.assertIn("OK", out)

    def test_layout_flag_flat_over_cliff_exits_1(self):
        with tempfile.TemporaryDirectory() as root:
            # 15 rules > RULE_CLIFF (14); whole file counted, no section needed.
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(15)))
            rc, out, _ = self._run(["--root", root, "--layout", "flat"])
            self.assertEqual(rc, 1)
            self.assertIn("OVER (rules)", out)

    def test_manifest_driven_flat_no_flag_same_result(self):
        with tempfile.TemporaryDirectory() as root:
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(15)))
            self._manifest(root, "flat")
            rc, out, _ = self._run(["--root", root])
            self.assertEqual(rc, 1)
            self.assertIn("OVER (rules)", out)
            self.assertIn("index", out)

    def test_manifest_present_layout_roles_flag_overrides(self):
        with tempfile.TemporaryDirectory() as root:
            # Both a flat index AND a full role/shared corpus exist at root; the
            # manifest says flat, but --layout roles must force role discovery.
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(15)))
            self._manifest(root, "flat")
            self._corpus(root, shared_rules=2, role_rules=2)   # under cliff
            rc, out, _ = self._run(["--root", root, "--layout", "roles"])
            self.assertEqual(rc, 0)
            self.assertIn("pm", out)          # role discovery ran, not flat
            self.assertNotIn("Role (the whole index file", out)

    def test_no_manifest_no_flag_existing_behavior_unchanged(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)
            rc, out, _ = self._run(["--root", root])
            self.assertEqual(rc, 0)
            self.assertIn("Role (role + shared)", out)

    def test_flat_missing_index_clean_error_exit_2(self):
        with tempfile.TemporaryDirectory() as root:
            rc, _, err = self._run(["--root", root, "--layout", "flat"])
            self.assertEqual(rc, 2)
            self.assertIn("error", err.lower())

    def test_flat_baseline_write_then_ratchet_role_key_is_index(self):
        with tempfile.TemporaryDirectory() as root:
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(3)))
            bpath = os.path.join(root, "baseline.json")
            rc, _, _ = self._run(["--root", root, "--layout", "flat", "--write-baseline", bpath])
            self.assertEqual(rc, 0)
            data = mc.load_baseline(bpath)
            self.assertIn("index", data)
            self.assertEqual(data["index"]["rules"], 3)
            rc, out, _ = self._run(["--root", root, "--layout", "flat", "--baseline", bpath])
            self.assertEqual(rc, 0)
            self.assertIn("Ratchet OK", out)


class TestConsolidationSuggestionUnit(unittest.TestCase):
    def test_well_under_does_not_need_consolidation(self):
        load = mc.RoleLoad("pm", rules=4, always_lines=50, tokens=1000)
        self.assertFalse(mc.needs_consolidation(load))

    def test_just_below_near_line_does_not_fire(self):
        # Largest values strictly below 90% of every cliff: 12 < 12.6 rules,
        # 179 < 180 lines, 3599 < 3600 tokens.
        load = mc.RoleLoad("pm", rules=12, always_lines=179, tokens=3599)
        self.assertFalse(mc.needs_consolidation(load))

    def test_at_ninety_percent_of_lines_fires(self):
        load = mc.RoleLoad("pm", rules=4, always_lines=180, tokens=1000)
        self.assertTrue(mc.needs_consolidation(load))

    def test_at_ninety_percent_of_rules_fires(self):
        # ceil(0.9 * 14) = 13 is the first near value on the rules axis.
        load = mc.RoleLoad("pm", rules=13, always_lines=50, tokens=1000)
        self.assertTrue(mc.needs_consolidation(load))

    def test_over_cliff_fires(self):
        load = mc.RoleLoad("pm", rules=15, always_lines=50, tokens=1000)
        self.assertTrue(mc.needs_consolidation(load))

    def test_render_names_skill_tool_and_roles_on_one_line(self):
        per_role = [
            mc.RoleLoad("pm", rules=13, always_lines=50, tokens=1000),   # near
            mc.RoleLoad("dev", rules=4, always_lines=50, tokens=1000),   # fine
        ]
        line = mc.render_consolidation_suggestion(per_role)
        self.assertIsNotNone(line)
        self.assertNotIn("\n", line)                 # AC: ONE line
        self.assertIn("consolidate-memory", line)    # AC: names the skill
        self.assertIn("consolidate_pass.py", line)   # AC: names the tool
        self.assertIn("pm", line)
        self.assertNotIn("dev", line)                # only qualifying roles listed

    def test_render_none_when_all_roles_fine(self):
        per_role = [mc.RoleLoad("pm", rules=4, always_lines=50, tokens=1000)]
        self.assertIsNone(mc.render_consolidation_suggestion(per_role))


class TestConsolidationSuggestionMainIntegration(_CorpusBuilderMixin, unittest.TestCase):
    def _run(self, args):
        buf, err = io.StringIO(), io.StringIO()
        with redirect_stdout(buf), redirect_stderr(err):
            rc = mc.main(args)
        return rc, buf.getvalue(), err.getvalue()

    def test_near_cliff_suggests_and_still_exits_0(self):
        with tempfile.TemporaryDirectory() as root:
            # effective 13 rules: >= 90% of the 14-rule cliff, but not over it.
            self._corpus(root, shared_rules=8, role_rules=5)
            rc, out, _ = self._run(["--root", root])
            self.assertEqual(rc, 0)                  # AC: exit semantics unchanged
            self.assertIn("consolidate-memory", out)

    def test_under_near_line_no_suggestion(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=2, role_rules=2)
            rc, out, _ = self._run(["--root", root])
            self.assertEqual(rc, 0)
            self.assertNotIn("consolidate", out)

    def test_over_cliff_suggests_and_still_exits_1(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=13, role_rules=5)   # effective 18 > 14
            rc, out, _ = self._run(["--root", root])
            self.assertEqual(rc, 1)                  # AC: exit semantics unchanged
            self.assertIn("consolidate-memory", out)

    def test_ratchet_mode_carries_suggestion_without_exit_change(self):
        with tempfile.TemporaryDirectory() as root:
            # Over the absolute cliff but ratchet-clean: rc must stay 0 (ratchet
            # semantics), with the suggestion line present in the report.
            self._corpus(root, shared_rules=20, role_rules=5)
            bpath = os.path.join(root, "baseline.json")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(mc.main(["--root", root, "--write-baseline", bpath]), 0)
            rc, out, _ = self._run(["--root", root, "--baseline", bpath])
            self.assertEqual(rc, 0)
            self.assertIn("Ratchet OK", out)
            self.assertIn("consolidate-memory", out)

    def test_write_baseline_mode_never_suggests(self):
        with tempfile.TemporaryDirectory() as root:
            self._corpus(root, shared_rules=20, role_rules=5)   # far over the cliff
            bpath = os.path.join(root, "baseline.json")
            rc, out, _ = self._run(["--root", root, "--write-baseline", bpath])
            self.assertEqual(rc, 0)
            self.assertNotIn("consolidate", out)

    def test_flat_layout_near_cliff_suggests(self):
        with tempfile.TemporaryDirectory() as root:
            # 13 whole-file rules: near the 14-rule cliff in flat layout.
            self._flat_index(root, "".join(f"- **R{i}:** x\n" for i in range(13)))
            rc, out, _ = self._run(["--root", root, "--layout", "flat"])
            self.assertEqual(rc, 0)
            self.assertIn("consolidate-memory", out)
            self.assertIn("index", out)

    def test_linter_has_no_invocation_path(self):
        # AC: the linter performs no invocation of the pass under any code path.
        # Tripwire, not proof: the tool must stay free of process-spawning calls.
        src_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "memory_cliff.py"
        )
        with open(src_path, encoding="utf-8") as f:
            src = f.read()
        for needle in ("subprocess", "os.system", "popen", "os.exec"):
            self.assertNotIn(needle, src)


if __name__ == "__main__":
    unittest.main()
