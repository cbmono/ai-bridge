Slice 1 of 6 (products). The 35-endpoint inventory becomes an exported route→capability table; `registerProxyRoutes` refuses to register anything the table does not name; product reads are the first domain on the session→capability→forward pipeline.

Verified: 277/0 locally, 10/10 non-deploy checks green on [run 33430116558](https://github.com/alteos-gmbh/monorepo/actions/runs/33430116558). Eight mutations each turn a named test red.

### Criteria (10 ✓ / 8 ✗ — every ✗ is a later slice or task-001)

| # | Criterion | | Verified by |
|---|---|---|---|
| 1 | Inventory written down and verified | ✓ | 38 confirmed; 3 non-configuration-service ⇒ 35 proxied |
| 2 | Mapping in code, unmapped route fails to register | ✓ | `route-capability-map.test.ts` walks live `onRoute`, 20/0 |
| 3 | Deny-by-default at both layers | ✗ | 401/403 on every registered route; only `readConfig` registered here |
| 4 | `readConfig` gates every GET, by iterating the table | ✓ | all 24 GET entries |
| 5 | `writeConfig` gates exactly the 5 mutating routes | ✓ | set equality, no correction needed |
| 6 | `editTemplates` axes separate in both directions | ✗ | mapping half done; wire half needs the emails slice |
| 7 | `promoteProd` reads deploy target from body, fails closed | ✗ | not registered — `registerProxyRoutes` throws on it |
| 8 | Simulations classified deliberately, not by verb | ✓ | `readConfig`, justified at `SIMULATION_IS_A_READ`; test pins the reason |
| 9 | Per-user attribution via real `x-user-id` | ✗ | headers done; end-to-end needs a deployed BFF (task-001) |
| 10 | Multipart fidelity, ≥50 MB, no BFF timeout | ✗ | multipart slice; non-GET routes refuse to register |
| 11 | Binary passthrough byte-identical | ✗ | binary slice |
| 12 | Exact status passthrough, 401 the only interception | ✓ | 200/204/400/404/409/422/500 + upstream 401 all unmodified |
| 13 | Route-for-route, no aggregation or reshaping | ✓ | `rawPayload.equals(...)`, content-type preserved |
| 14 | Neither non-configuration-service call proxied | ✓ | `scope-boundary.test.ts` 4/0 |
| 15 | Acceptance test, both directions | ✗ | needs deployed BFF + real sessions (task-001) |
| 16 | Residual risk stated in corrected form | ✓ | see Notes |
| 17 | Sliced, one domain each, under ~500 lines | ✗ | slice named, but +1,657 — see below |
| 18 | Green on what the diff triggers | ✓ | `bff/studio/**` only; SPA workflow not triggered |

### Notes

- **A grep-derived inventory would have been short by 8 and looked complete.** `emails.ts` holds a literal NUL byte, so `grep` calls it binary and exits 0 — hiding all eight email endpoints. Use `grep -a`, or read the modules.
- **The environment axis is a property of the deployment (`STUDIO_ENV`), never the request.** `Origin`-derived would evaluate production traffic at `dev`. Defaults to `prod`.
- **Deny-by-default lives at registration** — `registerProxyRoutes` throws, so the server does not boot on an unmapped route. No runtime fallback exists.
- **Residual risk:** `configuration-service` stays directly reachable, so this proves the BFF path is closed, not that no path exists. Fix is task-009; v1's retirement is its precondition, not the fix.
- **Remaining slices:** (2) product writes + multipart, (3) binary downloads, (4) partners, (5) emails + system, (6) workflows + deploy.

⚠️ **Size, needs your call:** +1,657/−54 vs the 500 heuristic — ~570 doc comment, 751 tests, ~150 inventory data. The split I considered (table-only / plumbing+routes) was declined: criterion 2 cannot be proven by either half alone.

