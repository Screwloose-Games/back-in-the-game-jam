#!/usr/bin/env python3
"""Tests for `pipeline.py issue create` and `issue update`.

Runs standalone (`python tools/pipeline/test_issue_commands.py`) like the sibling
test files, and also under pytest.

Entirely offline. Writes are captured by a RecordedRunner -- the mutation-side
twin of RecordedClient -- so the exact gh commands, in the exact order, with the
body on stdin, are assertable without a token or a scratch repository.

test_a_dry_run_never_constructs_a_real_runner is the one that matters most.
Dry-run-by-default is the only thing standing between a typo and a live board,
and it is enforced by which runner gets built rather than by an `if` inside the
command, so that is what the test checks.
"""

from __future__ import annotations

import contextlib
import io
import sys
from pathlib import Path

from pipeline_cli import board, cli, github
from pipeline_cli.commands import issue as issue_command
from pipeline_cli.common import EXIT_CANNOT_RUN, EXIT_CHECK_FAILED, EXIT_OK

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parents[1]

REPO = "Screwloose-Games/test-repo"
GOOD_PATH = "assets/art/3d/props/rain_barrel/sm_rain_barrel.gltf"

CREATE_ARGS = [
    "issue",
    "create",
    "--repo",
    REPO,
    "--template",
    "create_model",
    "--name",
    "rain barrel",
    "--description",
    "A wooden rain barrel.",
    "--field",
    "dimentions=1m x 1m x 1m",
]

ISSUE_FIELDS = {
    "organization": {
        "issueFields": {
            "nodes": [
                {"__typename": "IssueFieldText", "id": "IFT_test", "name": "filepath"},
                {
                    "__typename": "IssueFieldSingleSelect",
                    "id": "IFSS_test",
                    "name": "Priority",
                    "options": [
                        {"id": "opt_high", "name": "High"},
                        {"id": "opt_low", "name": "Low"},
                    ],
                },
            ]
        }
    }
}


REPO_ISSUE_FIELDS = {
    "repository": {
        "viewerCanSeeIssueFields": True,
        "issueFields": ISSUE_FIELDS["organization"]["issueFields"],
    }
}


def issue_payload(body: str, fields: dict | None = None) -> dict:
    """One issue in the shape ISSUE_BY_NUMBER_QUERY returns."""
    nodes = [
        {"__typename": "IssueFieldTextValue", "value": value, "field": {"name": name}}
        for name, value in (fields or {}).items()
    ]
    return {
        "repository": {
            "issue": {
                "id": "I_test",
                "number": 7,
                "url": f"https://github.com/{REPO}/issues/7",
                "title": "Create 3D model for rain barrel",
                "body": body,
                "issueFieldValues": {"nodes": nodes},
            }
        }
    }


class FakeClient:
    """Answers the queries the issue commands make, routed by query text.

    A single canned payload would let the repository-scoped lookup appear to work
    while never actually being asked for -- the org fallback would quietly cover
    for it. Routing is what makes that path assertable.
    """

    name = "fake"

    def __init__(self, payload=None, error: str = "", *, repo_payload=None, issue=None) -> None:
        self.payload = payload if payload is not None else ISSUE_FIELDS
        self.repo_payload = repo_payload
        self.issue = issue
        self.error = error
        self.queries: list[str] = []

    def execute(self, query, variables):
        self.queries.append(query)
        if self.error:
            raise github.TransportError(self.error)
        if "issue(number:" in query:
            if self.issue is None:
                raise github.TransportError("no issue payload configured")
            return self.issue
        if "repository(" in query and "issueFields" in query:
            return self.repo_payload if self.repo_payload is not None else {}
        return self.payload

    def asked_repository_first(self) -> bool:
        """True when a repository issue-field query preceded any org one."""
        for query in self.queries:
            if "issueFields" not in query:
                continue
            return "repository(" in query
        return False


class Harness:
    """Swap the two seams the issue commands reach the network through."""

    def __init__(self, responses=None, client=None) -> None:
        self.runner = github.RecordedRunner(responses=list(responses or []))
        self.client = client if client is not None else FakeClient()

    def __enter__(self):
        self._runner_factory = issue_command.pick_runner
        self._choose = board.choose_client
        issue_command.pick_runner = lambda apply: self.runner
        board.choose_client = lambda token: self.client
        return self

    def __exit__(self, *exc):
        issue_command.pick_runner = self._runner_factory
        board.choose_client = self._choose
        return False


def run(argv, harness: Harness | None = None) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = cli.main(argv)
    return code, out.getvalue(), err.getvalue()


def created(extra=None) -> tuple[Harness, int, str]:
    harness = Harness()
    with harness:
        code, out, _ = run([*CREATE_ARGS, "--filepath", GOOD_PATH, *(extra or [])])
    return harness, code, out


# --------------------------------------------------------------------------
# Dry run is the default


def test_a_dry_run_never_constructs_a_real_runner():
    assert isinstance(issue_command.pick_runner(False), github.DryRunRunner)


def test_a_dry_run_says_nothing_was_created():
    _, code, out = created()
    assert code == EXIT_OK
    assert "Nothing was created" in out
    assert "--apply" in out


def test_apply_changes_the_closing_line():
    harness = Harness()
    with harness:
        code, out, _ = run([*CREATE_ARGS, "--filepath", GOOD_PATH, "--apply"])
    assert code == EXIT_OK
    assert "Nothing was created" not in out
    assert "Created " in out


# --------------------------------------------------------------------------
# The call sequence


def test_the_three_writes_happen_in_order():
    harness, _, _ = created()
    argv = harness.runner.argv()
    assert argv[0][:2] == ["issue", "create"]
    assert argv[1][:2] == ["project", "item-add"]
    assert argv[-1][:2] == ["api", "graphql"]


def test_the_body_arrives_on_stdin_not_in_argv():
    # Several KB of checklist would hit argv limits and shell quoting.
    harness, _, _ = created()
    args, stdin = harness.runner.calls[0]
    assert "--body-file" in args and args[args.index("--body-file") + 1] == "-"
    assert stdin and "### Description" in stdin
    assert not any("### Description" in arg for arg in args)


def test_the_generated_subtasks_block_is_in_the_created_body():
    harness, _, _ = created()
    _, stdin = harness.runner.calls[0]
    assert "<!-- pipeline:subtasks:start -->" in stdin


def test_the_template_label_is_applied():
    harness, _, _ = created()
    args = harness.runner.calls[0][0]
    assert "--label" in args and "3d model" in args


def test_the_project_item_is_added_by_number_not_by_title():
    # A project title is renameable from the UI; the number is not.
    harness, _, _ = created()
    args = harness.runner.argv()[1]
    assert args[2] == str(board.DEFAULT_PROJECT_NUMBER)
    assert "--owner" in args and board.DEFAULT_ORG in args


def test_no_project_skips_the_board():
    harness, _, _ = created(["--no-project"])
    assert not any(args[:2] == ["project", "item-add"] for args in harness.runner.argv())


def test_the_filepath_field_id_is_discovered_by_name_not_hardcoded():
    harness, _, _ = created()
    mutation = harness.runner.calls[-1]
    assert "-f" in mutation[0]
    assert "fieldId=IFT_test" in mutation[0], "the id must come from the query, not a constant"
    assert f"value={GOOD_PATH}" in mutation[0]
    assert "setIssueFieldValue" in (mutation[1] or "")


def test_no_filepath_means_no_field_mutation():
    harness = Harness()
    with harness:
        run(CREATE_ARGS)
    assert not any(args[:2] == ["api", "graphql"] for args in harness.runner.argv())


# --------------------------------------------------------------------------
# Refusals happen before anything is written


def test_a_placeholder_filepath_refuses_and_writes_nothing():
    harness = Harness()
    with harness:
        code, _, err = run([*CREATE_ARGS, "--filepath", "assets/art/3d/{cat}/sm_{obj}.gltf"])
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "placeholder" in err


def test_a_nonstandard_filename_refuses_without_force():
    harness = Harness()
    with harness:
        code, _, err = run(
            [*CREATE_ARGS, "--filepath", "assets/art/3d/props/rain_barrel/sm_RainBarrel.gltf"]
        )
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "--force" in err


def test_force_lets_a_nonstandard_filename_through_with_a_warning():
    harness = Harness()
    with harness:
        code, out, _ = run(
            [
                *CREATE_ARGS,
                "--filepath",
                "assets/art/3d/props/rain_barrel/sm_RainBarrel.gltf",
                "--force",
            ]
        )
    assert code == EXIT_OK
    assert "WARN" in out
    assert harness.runner.calls


def test_a_required_field_with_no_answer_refuses_before_writing():
    harness = Harness()
    with harness:
        code, _, err = run(
            ["issue", "create", "--repo", REPO, "--template", "create_model", "--name", "x"]
        )
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "Description" in err


# --------------------------------------------------------------------------
# Degrading rather than failing


def test_an_unreachable_issue_field_warns_and_still_creates():
    # The body already carries the path; losing a board column is not a reason
    # to fail an issue that already exists.
    harness = Harness(client=FakeClient(error="Field 'issueFields' doesn't exist"))
    with harness:
        code, out, _ = run([*CREATE_ARGS, "--filepath", GOOD_PATH])
    assert code == EXIT_OK
    assert "WARN" in out
    assert GOOD_PATH in out
    assert harness.runner.argv()[0][:2] == ["issue", "create"]


def test_a_missing_field_name_says_what_to_set_by_hand():
    harness = Harness(client=FakeClient(payload={"organization": {"issueFields": {"nodes": []}}}))
    with harness:
        code, out, _ = run([*CREATE_ARGS, "--filepath", GOOD_PATH])
    assert code == EXIT_OK
    assert "set it by hand" in out


def test_a_gh_failure_is_explained_with_the_write_scope():
    message = github.explain_transport_error(
        "your token has insufficient_scopes for project", write=True
    )
    assert "gh auth refresh -h github.com -s project" in message
    assert "read:project" not in message


# --------------------------------------------------------------------------
# issue update


def test_update_with_no_flags_refuses():
    harness = Harness()
    with harness:
        code, _, err = run(["issue", "update", "7", "--repo", REPO])
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "nothing to change" in err


def test_update_filepath_sets_the_issue_field():
    harness = Harness()
    with harness:
        code, _, _ = run(["issue", "update", "7", "--repo", REPO, "--filepath", GOOD_PATH])
    assert code == EXIT_OK
    argv = harness.runner.argv()
    assert argv[0][:2] == ["issue", "view"]
    assert argv[-1][:2] == ["api", "graphql"]
    assert f"value={GOOD_PATH}" in argv[-1]


def test_update_validates_the_filepath_exactly_as_create_does():
    harness = Harness()
    with harness:
        code, _, err = run(["issue", "update", "7", "--repo", REPO, "--filepath", "res://{x}.gltf"])
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "placeholder" in err


def test_update_batches_the_edit_flags_into_one_call():
    harness = Harness()
    with harness:
        run(
            [
                "issue",
                "update",
                "7",
                "--repo",
                REPO,
                "--title",
                "New title",
                "--add-label",
                "blocked",
                "--remove-label",
                "ready",
            ]
        )
    edits = [args for args in harness.runner.argv() if args[:2] == ["issue", "edit"]]
    assert len(edits) == 1
    assert "--title" in edits[0] and "--add-label" in edits[0] and "--remove-label" in edits[0]


def test_update_state_uses_close_rather_than_an_edit_flag():
    harness = Harness()
    with harness:
        run(["issue", "update", "7", "--repo", REPO, "--state", "closed"])
    assert harness.runner.argv() == [["issue", "close", "7", "--repo", REPO]]


def test_update_priority_resolves_the_option_id():
    harness = Harness()
    with harness:
        run(["issue", "update", "7", "--repo", REPO, "--priority", "high"])
    mutation = harness.runner.argv()[-1]
    assert "optionId=opt_high" in mutation, "the option must be matched case-insensitively"


def test_update_priority_lists_the_options_when_the_value_is_unknown():
    harness = Harness()
    with harness:
        code, out, _ = run(["issue", "update", "7", "--repo", REPO, "--priority", "Urgent"])
    assert code == EXIT_OK
    assert "High" in out and "Low" in out


def test_resync_subtasks_needs_a_template():
    harness = Harness()
    with harness:
        code, _, err = run(["issue", "update", "7", "--repo", REPO, "--resync-subtasks"])
    assert code == EXIT_CANNOT_RUN
    assert harness.runner.calls == []
    assert "--template" in err


def test_resync_subtasks_warns_when_the_issue_has_no_block():
    harness = Harness(responses=[github.RunResult(0, "a body with no markers\n")])
    with harness:
        code, out, _ = run(
            [
                "issue",
                "update",
                "7",
                "--repo",
                REPO,
                "--resync-subtasks",
                "--template",
                "create_model",
            ]
        )
    assert code == EXIT_OK
    assert "no pipeline:subtasks block" in out
    assert not any(args[:2] == ["issue", "edit"] for args in harness.runner.argv())


def test_resync_subtasks_rewrites_only_the_block():
    body = (
        "### Subtasks\n\nkeep me\n\n"
        "<!-- pipeline:subtasks:start -->\n- [ ] stale\n<!-- pipeline:subtasks:end -->\n\ntrailer\n"
    )
    harness = Harness(responses=[github.RunResult(0, body)])
    with harness:
        code, _, _ = run(
            [
                "issue",
                "update",
                "7",
                "--repo",
                REPO,
                "--resync-subtasks",
                "--template",
                "create_model",
            ]
        )
    assert code == EXIT_OK
    edit = next(call for call in harness.runner.calls if call[0][:2] == ["issue", "edit"])
    updated = edit[1]
    assert "keep me" in updated and "trailer" in updated
    assert "- [ ] stale" not in updated
    assert "- [ ] The model faces +Y in Blender." in updated


# --------------------------------------------------------------------------
# issue sync-filepath

SYNC_ARGS = ["issue", "sync-filepath", "7", "--repo", REPO]


def body_with(path: str) -> str:
    return f"### Description\n\nA rain barrel.\n\n### Save File Path\n\n{path}\n"


def synced(path: str, *, extra=None, fields=None, responses=None, repo_payload=None):
    """Run sync-filepath over a body asking for `path`."""
    client = FakeClient(
        issue=issue_payload(body_with(path), fields),
        repo_payload=repo_payload,
    )
    harness = Harness(responses=responses, client=client)
    with harness:
        code, out, err = run([*SYNC_ARGS, "--apply", *(extra or [])])
    return harness, client, code, out, err


def test_sync_filepath_sets_the_field_from_the_body():
    harness, _, code, _, _ = synced(GOOD_PATH)
    assert code == EXIT_OK
    mutation = harness.runner.argv()[-1]
    assert mutation[:2] == ["api", "graphql"]
    assert f"value={GOOD_PATH}" in mutation
    assert "fieldId=IFT_test" in mutation


def test_sync_filepath_asks_the_repository_for_the_field_ids_first():
    # Without this the repo-scoped lookup is dead code: the org fallback would
    # answer, the test would pass, and the workflow would still be unable to run.
    _, client, code, _, _ = synced(GOOD_PATH, repo_payload=REPO_ISSUE_FIELDS)
    assert code == EXIT_OK
    assert client.asked_repository_first()


def test_sync_filepath_falls_back_to_the_org_query_when_the_repo_one_is_empty():
    harness, client, code, _, _ = synced(GOOD_PATH)  # repo_payload defaults to {}
    assert code == EXIT_OK
    assert any("organization(" in query for query in client.queries)
    assert "fieldId=IFT_test" in harness.runner.argv()[-1]


def test_sync_filepath_reads_the_body_through_the_client_not_the_runner():
    """A dry run must still see the real body, and print the real decision.

    Run against a genuine DryRunRunner rather than the Harness's recorder, since
    the property under test is exactly what pick_runner hands back for --apply's
    absence. A body read through the runner would come back as DRY_RUN_NODE_ID --
    which is what makes `issue update --resync-subtasks` useless without --apply.
    """
    client = FakeClient(issue=issue_payload(body_with(GOOD_PATH)))
    dry = github.DryRunRunner()
    harness = Harness(client=client)
    with harness:
        issue_command.pick_runner = lambda apply: dry
        code, out, _ = run(SYNC_ARGS)
    assert code == EXIT_OK
    assert client.queries, "a dry run must still read"
    assert GOOD_PATH in out, "the real body reached the decision, not canned stdout"
    assert "Nothing was changed" in out
    # DryRunRunner prints rather than sends; the mutation is only ever described.
    assert any(call[:2] == ["api", "graphql"] for call in dry.calls)


def test_sync_filepath_skips_the_template_placeholder_without_failing():
    # create_model.yaml ships this as the field's default, so an artist who does
    # not edit it is the common case -- not an error, and not something to write
    # to the board, where it would read as delivered.
    default = "assets/art/3d/{category}/{object_name}/sm_{object_name}.gltf"
    harness, _, code, out, _ = synced(default)
    assert code == EXIT_OK
    assert "placeholder" in out
    assert not any(args[:2] == ["api", "graphql"] for args in harness.runner.argv())


def test_sync_filepath_skips_a_directory_and_says_so():
    # create_sfx.yaml and integrate_audio_file.yaml default to this. It has no
    # {braces}, so only check_path catches it.
    harness, _, code, out, _ = synced("game/.../object_name/sfx/")
    assert code == EXIT_OK
    assert "directory" in out
    assert not any(args[:2] == ["api", "graphql"] for args in harness.runner.argv())


def test_sync_filepath_comments_once_when_the_path_is_unusable():
    harness, _, _, _, _ = synced("assets/art/3d/{category}/sm_{object_name}.gltf")
    comments = [call for call in harness.runner.calls if call[0][:2] == ["issue", "comment"]]
    assert len(comments) == 1
    args, stdin = comments[0]
    assert "--edit-last" in args and "--create-if-none" in args
    assert issue_command.COMMENT_MARKER in (stdin or "")


def test_a_good_path_replaces_an_earlier_complaint_without_creating_one():
    # --edit-last *without* --create-if-none: it rewrites a previous complaint if
    # there is one and fails harmlessly if there is not, so an issue that was
    # always fine never acquires a comment.
    harness, _, code, _, _ = synced(GOOD_PATH)
    assert code == EXIT_OK
    comments = [call for call in harness.runner.calls if call[0][:2] == ["issue", "comment"]]
    assert len(comments) == 1
    args, stdin = comments[0]
    assert "--edit-last" in args
    assert "--create-if-none" not in args, "a clean issue must not gain a comment"
    assert "Resolved" in (stdin or "")


def test_a_missing_earlier_comment_is_not_reported_as_a_problem():
    harness, _, code, out, _ = synced(
        GOOD_PATH, responses=[github.RunResult(1, "", "no comments found")]
    )
    assert code == EXIT_OK
    assert "could not comment" not in out
    assert "WARN" not in out


def test_sync_filepath_can_be_told_not_to_comment():
    harness, _, _, _, _ = synced("a/{b}.gltf", extra=["--no-comment"])
    assert harness.runner.calls == []


def test_sync_filepath_still_sets_a_nonstandard_path():
    # A column an artist can see and correct beats a blank one nobody can read.
    odd = "assets/art/3d/props/rain_barrel/barrel.gltf"
    harness, _, code, out, _ = synced(odd)
    assert code == EXIT_OK
    assert "WARN" in out
    assert f"value={odd}" in harness.runner.argv()[-1]


def test_sync_filepath_skips_a_body_with_no_path_heading():
    client = FakeClient(issue=issue_payload("## Notes\n\nhand written\n"))
    harness = Harness(client=client)
    with harness:
        code, out, _ = run([*SYNC_ARGS, "--apply"])
    assert code == EXIT_OK
    assert harness.runner.calls == []
    assert "no answer under a filepath heading" in out


def test_sync_filepath_does_nothing_when_the_field_already_matches():
    harness, _, code, out, _ = synced(GOOD_PATH, fields={"filepath": GOOD_PATH})
    assert code == EXIT_OK
    assert harness.runner.calls == []
    assert "already matches" in out


def test_only_if_empty_leaves_a_populated_field_alone():
    harness, _, code, out, _ = synced(
        GOOD_PATH, fields={"filepath": "assets/art/3d/old/sm_old.gltf"}, extra=["--only-if-empty"]
    )
    assert code == EXIT_OK
    assert harness.runner.calls == []
    assert "only-if-empty" in out


def test_sync_filepath_fails_when_the_mutation_is_refused():
    # set_issue_text_field degrades a failed write to a warning, which is right
    # for `issue create` and wrong here: this command exists to do that write, so
    # a green run that set nothing would be worse than a red one.
    # --no-comment so the queued failure lands on the mutation and nothing else.
    harness, _, code, _, err = synced(
        GOOD_PATH,
        extra=["--no-comment"],
        responses=[github.RunResult(1, "", "Resource not accessible by integration")],
    )
    assert code == EXIT_CHECK_FAILED
    assert "could not set filepath" in err
    assert "PIPELINE_ISSUE_FIELD_TOKEN" in err


def test_a_failed_comment_does_not_fail_a_run_that_set_the_field():
    odd = "assets/art/3d/props/rain_barrel/barrel.gltf"
    harness, _, code, out, _ = synced(
        odd, responses=[github.RunResult(1, "", "comment API is having a day")]
    )
    assert code == EXIT_OK
    assert "could not comment" in out
    assert f"value={odd}" in harness.runner.argv()[-1]


# --------------------------------------------------------------------------


def run_standalone() -> int:
    tests = [
        (name, obj)
        for name, obj in sorted(globals().items())
        if name.startswith("test_") and callable(obj)
    ]
    failures = 0
    for name, test in tests:
        try:
            test()
        except AssertionError as exc:
            failures += 1
            print(f"FAIL  {name}\n      {exc}")
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"ERROR {name}\n      {type(exc).__name__}: {exc}")
        else:
            print(f"ok    {name}")

    print(f"\n{len(tests) - failures}/{len(tests)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(run_standalone())
