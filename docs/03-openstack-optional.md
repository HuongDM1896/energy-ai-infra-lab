# Step 3 (optional) — OpenStack / virtualization basics

Some Vietnamese GPU-cloud teams (e.g. Viettel IDC postings) ask for basic
VMware or OpenStack knowledge. You do not need to master it — aim to be able to
say "I deployed a single-node OpenStack and launched VMs/networks".

## Minimal path
1. Get one Linux VM or a Grid'5000 node with ≥ 8 GB RAM, Ubuntu LTS.
2. Install **DevStack** (single-node OpenStack for learning) following the
   official DevStack guide: https://docs.openstack.org/devstack/latest/
3. In Horizon (web UI) or the `openstack` CLI:
   - create a network + subnet + router
   - upload an image, create a flavor, launch a VM
   - attach a volume
4. Write a short `docs/openstack-notes.md` with screenshots/commands.

## Concepts to explain
Nova (compute), Neutron (network), Cinder (block storage), Glance (images),
Keystone (identity); hypervisor (KVM); how GPU passthrough to a VM works at a high level.

Honest note: DevStack is for learning, not production — say so if asked.
