# Upload to GitHub

## 1) Create a new GitHub repository

Create an empty repo in GitHub UI, for example: `oboy/Synapse`.

## 2) Add remote and push

```bash
git remote add origin git@github.com:<YOUR_NAME>/Synapse.git
git push -u origin codex/v1
```

If you want `main` as default branch:

```bash
git checkout -b main
git merge --ff-only codex/v1
git push -u origin main
```
