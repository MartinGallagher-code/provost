#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# provost/transform/melt.sh — the extract-output transform (tidy melt + schema-union
# helpers). First-party provost code; edit it here.
#
# Functions: _core_melt_tidy, _core_union_header, _core_align_rows.
# Originally imported from EnvoyCapture/lib/_core.sh
# @ 8639a6ef54fe5867aba8bee81171c5abd344adb3 (2026-07-05); maintained locally since.

# Union of two TSV header lines, by column name: all of $1's columns in order,
# then any of $2's columns not already present. Prints the tab-joined header.
_core_union_header () {
    awk -v old="$1" -v new="$2" 'BEGIN{
        n1=split(old,a,"\t"); n2=split(new,b,"\t"); m=0
        for(i=1;i<=n1;i++) if(!(a[i] in seen)){out[++m]=a[i]; seen[a[i]]=1}
        for(j=1;j<=n2;j++) if(!(b[j] in seen)){out[++m]=b[j]; seen[b[j]]=1}
        s=""; for(k=1;k<=m;k++) s=s (k>1?"\t":"") out[k]; print s
    }'
}

# Re-map data rows (read from stdin, no header) from a source header's column
# order to a target header's, matching by NAME and blanking columns the source
# lacks. Prints the aligned data rows (no header). This keeps a dataset
# rectangular across schema changes — added, removed, or reordered columns.
_core_align_rows () {
    awk -F'\t' -v OFS='\t' -v sh="$1" -v th="$2" '
        BEGIN{ ns=split(sh,sc,"\t"); for(i=1;i<=ns;i++) sidx[sc[i]]=i; nt=split(th,tc,"\t") }
        {
            line=""
            for(j=1;j<=nt;j++){ v=(tc[j] in sidx)?$(sidx[tc[j]]):""; line=line (j>1?OFS:"") v }
            print line
        }'
}

# Reshape a wide extract (header + one data row) into tidy long form when its
# columns are a single repeating group named `<prefix><N>.<field>` (e.g.
# entry1.permissions, entry2.permissions, …, as emitted by table strategies like
# tar-listing / pipe-table). Emits one row per record with a `capture` group id
# ($2) and an `n` index, the shared fields, and any non-repeating scalar columns
# (repeated per row). Anything that is NOT a single clean repeating table —
# plain scalars (`a b`), or multiple record prefixes — is passed through
# unchanged, so this only reshapes table-shaped output.
#
# One exception: a single-column, single-row wide (one key/value observation —
# the shape of a version banner or one-line status) is emitted in long form
# (`field`/`value` columns), the canonical tidy layout for a lone observation
# of a lone variable. Multi-column snapshots keep their wide layout.
_core_melt_tidy () {
    local tsv="$1" capid="${2:-}"
    printf '%s\n' "$tsv" | awk -F'\t' -v OFS='\t' -v cap="$capid" '
        { L[NR]=$0 }
        NR==1 { nf=NF; for(i=1;i<=NF;i++) H[i]=$i }
        NR==2 { for(i=1;i<=nf;i++) V[i]=$i }
        END {
          if (NR!=2) { for(r=1;r<=NR;r++) print L[r]; exit }   # only header+1row is meltable
          np=0; nfld=0; nidx=0; nsc=0
          for(i=1;i<=nf;i++){
            h=H[i]; d=index(h,"."); isgroup=0
            if (d>1){
              left=substr(h,1,d-1); field=substr(h,d+1)
              if (match(left,/[0-9]+$/)){
                num=substr(left,RSTART)+0; pref=substr(left,1,RSTART-1)
                if (pref!=""){
                  isgroup=1
                  if(!(pref in seenp)){seenp[pref]=1; np++}
                  key=num SUBSEP field; cell[key]=V[i]
                  if(!(num in seenix)){seenix[num]=1; idxs[++nidx]=num}
                  if(!(field in seenf)){seenf[field]=1; flds[++nfld]=field}
                }
              }
            }
            if(!isgroup) scalidx[++nsc]=i
          }
          if (np!=1 || nfld==0){
            # lone key/value observation -> long form (see header comment)
            if (nf==1 && H[1]!="" && V[1]!=""){ print "field" OFS "value"; print H[1] OFS V[1]; exit }
            print L[1]; print L[2]; exit                          # not a single table
          }
          for(a=1;a<=nidx;a++) for(b=a+1;b<=nidx;b++) if(idxs[b]<idxs[a]){t=idxs[a];idxs[a]=idxs[b];idxs[b]=t}
          hdr=(cap!=""?"capture" OFS:"") "n"
          for(k=1;k<=nfld;k++) hdr=hdr OFS flds[k]
          for(s=1;s<=nsc;s++) hdr=hdr OFS H[scalidx[s]]
          print hdr
          for(a=1;a<=nidx;a++){ ix=idxs[a]; row=(cap!=""?cap OFS:"") ix
            for(k=1;k<=nfld;k++){key=ix SUBSEP flds[k]; row=row OFS ((key in cell)?cell[key]:"")}
            for(s=1;s<=nsc;s++) row=row OFS V[scalidx[s]]
            print row }
        }'
}
