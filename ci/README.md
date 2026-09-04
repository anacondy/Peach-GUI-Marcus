# CI

`github-actions-test.yml` is a ready-to-use GitHub Actions workflow that runs the
same 63-test dependency-free suite as `tests/run-tests.sh`.

It is kept OUT of `.github/workflows/` in this clone because the automation token
that pushes this branch does not carry the `workflows` permission GitHub requires
to create or update workflow files. Once that permission is granted, enable it
with:

    mkdir -p .github/workflows
    git mv ci/github-actions-test.yml .github/workflows/test.yml
    git commit -m "ci: enable test workflow"
