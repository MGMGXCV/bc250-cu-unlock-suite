# Sharing results

Generate a Markdown report with:

```bash
sudo ./bc250-unlock report
```

By default it is written under `./reports/` and intentionally omits hostname,
username and network addresses.

The report includes:

- kernel and Mesa version;
- upstream commit hashes;
- current live WGP dashboard;
- cached factory/candidate topology;
- latest compute and visual classifications;
- denylist;
- combined validation history;
- approved WGP set and nominal CU count;
- current CPU thread count, automatic re-arm state and recent CPU health-test records.

For GitHub issues, attach the report and describe the visible symptom separately.
Do not assume another board can safely use the same WGP set.
