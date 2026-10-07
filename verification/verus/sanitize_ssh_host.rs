// Host-side Verus model of sanitize_ssh_host output laws. Not linked into the app.
// Run: scripts/verify-verus.sh
use vstd::prelude::*;

verus! {

pub open spec fn is_shell_metachar(c: char) -> bool {
    c == '"' || c == '\'' || c == '`' || c == '$' || c == ';' || c == '&'
        || c == '|' || c == '<' || c == '>' || c == '\\'
}

pub open spec fn is_whitespace_ascii(c: char) -> bool {
    c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

pub open spec fn output_char_ok(c: char) -> bool {
    !is_whitespace_ascii(c) && !is_shell_metachar(c)
}

pub open spec fn sanitized_chars_ok(s: Seq<char>) -> bool {
    forall|i: int| 0 <= i < s.len() ==> output_char_ok(#[trigger] s[i])
}

proof fn empty_is_ok()
    ensures
        sanitized_chars_ok(Seq::empty()),
{
}

proof fn filtered_ascii_is_ok(raw: Seq<char>)
    requires
        forall|i: int|
            0 <= i < raw.len() ==> (' ' <= #[trigger] raw[i] && raw[i] <= '~'),
    ensures
        ({
            let out = raw.filter(|c: char| output_char_ok(c));
            sanitized_chars_ok(out)
        }),
{
}

} // verus!
