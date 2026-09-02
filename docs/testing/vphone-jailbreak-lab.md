# vphone-jb Nix wrap (Darwin Apple Silicon)

Jailbroken iOS research lab for Wawona Mode B proof. **Not** the Xcode Simulator.

Canonical automation lives in **L3′ [`wwn-vphone`](https://github.com/Wawona/wwn-vphone)**
(nixpkgs-only). This doc is the Wawona product pointer.

**Never** commit or GitHub-release a prebuilt iOS VM / `Disk.img` / IPSW.
The lab follows upstream [vphone-cli](https://github.com/Lakr233/vphone-cli):
download IPSWs at runtime, create VM, CFW `jb`, launch, SSH smoke.

## One command (any developer)

```bash
nix run github:Wawona/wwn-vphone#vphone-jb-lab
# or from this Wawona checkout (flake input):
nix run .#vphone-jb-lab
```

Full gates, flags, and artifacts: https://github.com/Wawona/wwn-vphone/blob/development/docs/lab.md

Operator owns Recovery SIP / `allow-research-guests` / `amfi` boot-arg. The
flake checks gates and never mutates them.

## agent-device (Wawona fork)

Pin: `github.com/Wawona/agent-device` (`0.18.3-wawona.N+`). MCP example in that
repo. After lab READY:

```bash
agent-device devices
agent-device packages status --device "vphone wawona-jb"
agent-device packages tipa install path/to/App.tipa --open --jit
agent-device packages apt install path/to/pkg.deb
agent-device packages debug attach com.example.app
```

Profile JSON is written by the lab (`vphone-wawona-jb.json`). Prefer device
name `vphone wawona-jb`.

## Mode B channels (do not conflate)

| Channel | Artifact | Tool |
|---|---|---|
| TrollStore | `.tipa` + ldid | `packages tipa` |
| Sileo / APT | `.deb` / tweaks | `packages apt` |

See `docs/mode-a-b.md` and agent rules `wawona-vphone-mode-b-packages`.
