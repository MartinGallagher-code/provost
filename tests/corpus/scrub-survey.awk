# tests/corpus/scrub-survey.awk -- for each FILE the secret scrub
# (lib/provost_redact.awk, PV-033) would change, "NAME<TAB>kind=n,...".
# Loaded after lib/provost_redact.awk:
#   LC_ALL=C awk -f lib/provost_redact.awk -f tests/corpus/scrub-survey.awk FILE...
function survey_flush(    k, n, K, i, j, t, s) {
    if (CUR == "") return
    n = 0; for (k in RC) K[++n] = k
    for (i = 2; i <= n; i++) { t = K[i]; for (j = i - 1; j >= 1 && K[j] > t; j--) K[j + 1] = K[j]; K[j + 1] = t }
    s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? "," : "") K[i] "=" RC[K[i]]
    if (s != "") print CUR "\t" s
    split("", RC)
}
FNR == 1 { survey_flush(); CUR = FILENAME; sub(/.*\//, "", CUR); scrub_reset() }
{ scrub_line($0) }
END { survey_flush() }
