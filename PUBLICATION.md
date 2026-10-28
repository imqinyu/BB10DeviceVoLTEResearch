# Publishing this handoff

1. Use the contents of this directory as the GitHub repository root. `README.md`
   is English; `README.zh-CN.md` is the optional Chinese overview.
2. Keep the evidence levels and Q20 incoming-call limitation visible in the
   README. Do not label all devices as fully working VoLTE.
3. Run `python tools/validate_release.py .`. Review any newly contributed logs
   before adding them, even if the automated scan passes.
4. Select a license with the relevant contributors. No new umbrella license
   was assigned to their existing distributions by this handoff.
5. A release ZIP may contain this directory. `MANIFEST.sha256` identifies the
   files in the prepared archive; it is a checksum list, not a signature.

Suggested repository name: `bb10-volte-research`.

Suggested short description:

> Experimental BB10 VoLTE research: native IMS configuration, software crypto
> provider recovery, status-bar indicator, contributed Unicom ports, and known
> incoming-call and hardware limitations.

The three original distributions are retained under `distributions/` for
historical comparison. Their old UI is Chinese. Use GitHub Releases for these
downloadable packages if that is more convenient than storing ZIPs in Git.

Do not upload the original workspace, `.ssh`, device backup folders, full
debug/SIP logs, or extracted firmware binaries. The prepared repository already
contains the material selected for publication. No GitHub upload has been made
by this handoff.
