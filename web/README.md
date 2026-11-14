# Hisab AI — web admin

A one-page admin console (`web/admin/index.html`) for every Hisab AI account:
revenue (MRR), users by plan, sign-ups, plan requests to approve or reject,
expiring plans, user search, set plan / months, block, notes and CSV export.

It signs in with Firebase (email + password) and reads Firestore directly.
Only the admin email written in the Firestore rules can open it.

## Deploy to your VPS

From your computer (in the repo folder):

```bash
bash tool/deploy_admin.sh root@200.234.32.137 admin.deencircle.online you@example.com
```

Then open https://admin.deencircle.online/gamex/dashboard/

The domain needs an **A record** pointing to the VPS IP. Run the same command
again after `git pull` to update the dashboard.
