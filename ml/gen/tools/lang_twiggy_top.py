"""`twiggy top [-n N] [--retained] app.wasm`: a box-drawn table (`│` header,
`┼` rule, `┊` cells) of WebAssembly items by size, with the trailing
`... and N more.` and `Σ [N Total Rows]` rows."""
from lib import Doc, fake

TOOL = "twiggy-top"

ITEMS = ["\"function names\" subsection", "data[0]", "data[1]", "data[3]", "elem[0]", "table[0]",
         "custom section 'producers'", "custom section '.debug_info'", "custom section '.debug_line'",
         "custom section '.debug_str'", "<wee_alloc::LargeAlloc as wee_alloc::AllocPolicy>::new_cell_for_free_list",
         "dlmalloc::dlmalloc::Dlmalloc::malloc::h{h}", "core::fmt::Formatter::pad::h{h}", "core::fmt::write::h{h}",
         "<&T as core::fmt::Debug>::fmt::h{h}", "alloc::raw_vec::finish_grow::h{h}", "__rust_realloc",
         "serde_json::de::Deserializer<R>::parse_any::h{h}", "wasm_bindgen::convert::closures::invoke3_mut::h{h}",
         "{w}::{w}::render::h{h}", "{w}_app::State::update::h{h}", "memcpy", "memset", "code[{n}]", "import env::abort",
         "export \"memory\"", "type[{n}]", "global[0]", "std::panicking::rust_panic_with_hook::h{h}"]


def generate(rng):
    d = Doc()
    retained = rng.random() < .35
    total = rng.randint(4000, 3000000)
    n = rng.randint(3, 25)
    sizes = sorted([int(total * rng.random() ** 3 * .3) + 1 for _ in range(n)], reverse=True)
    rows = []
    for s in sizes:
        it = rng.choice(ITEMS).format(h=fake.hexid(rng, 16), w=fake.word(rng), n=rng.randint(0, 900))
        cells = [str(s), f"{100 * s / total:.2f}%"]
        if retained:
            r = s + int(rng.random() ** 2 * total * .2)
            cells += [str(r), f"{100 * r / total:.2f}%"]
        rows.append(cells + [it])
    rest = rng.randint(10, 9000)
    rs = max(0, total - sum(sizes))
    more = [str(rs), f"{100 * rs / total:.2f}%"] + ([str(rs), f"{100 * rs / total:.2f}%"] if retained else []) + [f"... and {rest} more."]
    tot = [str(total), "100.00%"] + ([str(total), "100.00%"] if retained else []) + [f"Σ [{n + rest} Total Rows]"]
    if rng.random() < .8:
        rows.append(more)
    rows.append(tot)
    head = ["Shallow Bytes", "Shallow %"] + (["Retained Bytes", "Retained %"] if retained else []) + ["Item"]
    nnum = len(head) - 1
    w = [max(len(head[i]), max(len(r[i]) for r in rows)) for i in range(nnum)]
    d.line(" " + " │ ".join(head[i].rjust(w[i]) for i in range(nnum)) + " │ " + head[-1], "header", head)
    iw = max(len(r[-1]) for r in rows)
    d.skip("┼".join("─" * (w[i] + 2) for i in range(nnum)) + "┼" + "─" * (iw + 1))
    for r in rows:
        d.line(" " + " ┊ ".join(r[i].rjust(w[i]) for i in range(nnum)) + " ┊ " + r[-1], "row", r)
    return d
