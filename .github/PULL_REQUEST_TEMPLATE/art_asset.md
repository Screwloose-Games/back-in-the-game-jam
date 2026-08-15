<!--
For art: 3D models, textures, sprites, audio. Wrong template? Swap
?template=art_asset.md in the URL for prototype.md, or drop the parameter
entirely for the general one.

This template is short on purpose. Four validators already check naming, format,
poly budget, up-axis, canvas size, audio spec and .import sidecars, and they fail
the PR when they are unhappy -- so there is nothing to gain from re-checking them
by hand here. What is below is the part CI cannot decide.
-->

## The asset

<!-- What is it, and where does it live? assets/art/{category}/{object}/ -->

**Issue:** <!-- Closes #123 -- the issue's Subtasks list is the acceptance criteria. -->

## What a reviewer should look at

<!--
Optional, but this is the useful part of the description. Anything you want a
second opinion on: a silhouette that reads oddly at distance, a texture that may
be too busy for the GL Compatibility renderer, a poly count you had to fight.
-->

---

## Checked by hand, because CI cannot

The 3D workflow posts **nine rendered views as a comment on this PR**. Wait for it
before ticking these — it is the only way to see what actually landed.

- [ ] **Facing** — it faces the right way *in that render*. 
- [ ] **Dimensions** — they match the numbers **on the issue**, not just whatever the mesh currently measures.
- [ ] **Pivot** — at the world origin *and* in the right spot on the model.
- [ ] **Textures** — any wrong name was fixed at the exporter and re-exported. Nothing was renamed by hand.
- [ ] **In Godot** — it imports without errors and looks right in a scene, not only in Blender or the render.

## Committed together

- [ ] The mesh, the `.bin`, every texture, **and every `.import` sidecar** are all in this PR.
- [ ] I confirmed the `.import` files in the **OS file explorer**, not Godot's FileSystem dock.

## Spec — optional

- [ ] `{model}.gltf.spec.yaml` sits beside the model, with dimensions taken from the issue.

---
