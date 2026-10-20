# server-app-starter
an app saved on a server, updated via pipeline from server manager

# Guide: Forking and Deploying a New Application

Thanks to the automated CI/CD architecture running on your homeserver, deploying a new microservice is a fast, streamlined process. You don't need to touch the core server infrastructure; you simply fork the template, update the routing, and push your code.

Here is the step-by-step process to launch a new app (using `monthlybudget` as an example).

## Step 1: Fork the Starter Repository in GitHub
1. Go to your original `server-app-starter` repository on GitHub.
2. Click on **Use this template** (or **Fork**) to create a new repository.
3. Name your new repository (e.g., `monthlybudget`). 
4. **Crucial:** Ensure the new repository is set to **Private** so GitHub Actions can securely build and push the image to your private GHCR (GitHub Container Registry).

## Step 2: Clone the Repository to Your Server
Your Homeserver Deployment Manager constantly watches the `/server/apps` directory. You need to pull your new repository into this folder.

SSH into your server and run:
```bash
cd /server/apps
git clone https://github.com/rzepeda/monthlybudget.git
cd monthlybudget
```

## Step 3: Configure the Deployment Contract (`deploy.yml`)
The manager uses the `deploy.yml` file to know how to run your app. Open this file in your newly cloned repository and update the values to match your new app:

```yaml
version: 1
name: monthlybudget
image: ghcr.io/rzepeda/monthlybudget:main   # Update with your new repo name
container_name: srv-monthlybudget           # Unique container name
container_port: 8000

public:
  enabled: true
  subdomain: budget                         # This will create budget.agentictools.uk

database:
  postgres: true                            # Set to true if it needs the homeserver-data network
```

## Step 4: Configure App Secrets (Optional)
If your new application requires API keys, database credentials, or any private environment variables, **do not put them in your code**. Instead, use the secure secrets vault on your server.

1. Create a `.env` file in the secrets directory. **The filename must exactly match the folder name of your app** (e.g., `monthlybudget.env`).
   ```bash
   nano /server/secrets/monthlybudget.env
   ```
2. Add your private variables:
   ```env
   DATABASE_URL=postgres://user:password@postgres:5432/monthlybudget
   OPENAI_API_KEY=your_private_token_here
   ```
*The deployment manager will automatically inject these into your container at runtime.*

## Step 5: Add the Route to Cloudflare Tunnels
You need to tell Cloudflare to send traffic for your new subdomain to your Caddy proxy.

1. Go to your **Cloudflare Zero Trust Dashboard**.
2. Navigate to **Networks** -> **Tunnels** and select your active Caddy tunnel (e.g., `homeserver-caddy`).
3. Go to the **Public Hostname** tab and click **Add a public hostname**:
   * **Subdomain:** `budget` *(Must match what you put in `deploy.yml`)*
   * **Domain:** `agentictools.uk`
   * **Service Type:** `HTTP`
   * **URL:** `http://caddy-proxy:80` *(Make sure to include `http://` to prevent redirect loops)*
4. Click **Save hostname**.

## Step 6: Commit and Push (The Magic Step)
Now that the server is ready, trigger the automated pipeline by pushing your updated `deploy.yml` (and any new code) to GitHub.

You can do this from your local computer, Codespace, or the server itself:
```bash
git add deploy.yml
git commit -m "chore: setup deployment contract for monthlybudget"
git push origin main
```

### What happens next automatically?
1. **GitHub Actions** detects the push, compiles your Flutter/FastAPI code, and pushes a new Docker image to `ghcr.io/rzepeda/monthlybudget:main`.
2. Within 30 seconds, your **Homeserver Deployment Manager** reads the `deploy.yml`, pulls the fresh image, and starts `srv-monthlybudget`.
3. It securely mounts your secrets and connects the app to the database network.
4. It generates a new Caddy routing file for `budget.agentictools.uk`.
5. You can visit `https://budget.agentictools.uk` in your browser and see your new app live!


# Guide: Setting Up a Parallel Development (`dev`) Environment

To test new features, database changes, or experimental rules without risking downtime on your live production app, you can run a parallel **Development (`dev`)** container side-by-side with **Production (`main`)**. 

Because the Homeserver Deployment Manager (`manager.py`) treats each folder in `/server/apps` as an independent deployment contract, you do not need to clone your repository to the server. You simply map a second folder to the `:dev` Docker image tag.

---

### Prerequisite: Server Manager (`manager.py`) Requirements
Ensure `/opt/server-manager/manager.py` on your homeserver includes three key capabilities before running dual environments:
1. **Exact Container Name Matching:** Filters Docker containers by exact name (`c.name == container_name`) so `srv-monthlybudget` does not collide with `srv-monthlybudget-dev`.
2. **Volume Mount Support:** Reads the optional `volumes:` list from `deploy.yml` and passes it to `client.containers.run(..., volumes=volumes)`.
3. **Caddy Reloading:** Reloads `caddy-proxy` when a new `.caddy` site file is created so new subdomains do not return a blank page.

---

### Step 1: Enable Dynamic Branch Tagging in GitHub Actions
By default, a starter workflow might hardcode `value=main` in the Docker metadata step, which causes pushes to `dev` to overwrite your `:main` image. Update `.github/workflows/deploy.yml` in your repository so it triggers on both branches and tags the image dynamically with the branch name:

1. Under `on.push.branches`, include both `main` and `dev`:
   ```yaml
   on:
     push:
       branches:
         - main
         - dev

   In the Extract Docker metadata step (docker/metadata-action@v5), replace type=raw,value=main with type=ref,event=branch:

YAML
      - name: Extract Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=sha,prefix=sha-
Result: Pushing to main builds ghcr.io/rzepeda/monthlybudget:main. Pushing to dev builds ghcr.io/rzepeda/monthlybudget:dev.

Step 2: Create and Push the dev Branch on GitHub
If the :dev image does not exist in GHCR yet, manager.py will log a manifest unknown error until the branch is built for the first time.

Open your repository on GitHub.

Click the branch dropdown (currently showing main), type dev, and click Create branch: dev from 'main' (or run git checkout -b dev && git push -u origin dev locally).

Wait for the Actions tab on GitHub to finish building and publishing the :dev image.

Step 3: Create the Dev Deployment Contract on the Server (Config-Only)
You do not need to git clone the repository onto your server. The server only needs an empty directory containing a deploy.yml file.

SSH into your server and create a dedicated folder for the dev instance:

Bash
mkdir -p /server/apps/monthlybudget-dev
nano /server/apps/monthlybudget-dev/deploy.yml
Paste the development contract. Crucial: Ensure name, container_name, subdomain, and any persistent volumes paths are unique so they do not overwrite your production container or data:

YAML
version: 1
name: monthlybudget-dev                        # Unique name (creates monthlybudget-dev.caddy)
image: ghcr.io/rzepeda/monthlybudget:dev       # Watches the :dev image tag
container_name: srv-monthlybudget-dev          # Unique container name (prevents stopping prod)
container_port: 8000

public:
  enabled: true
  subdomain: dev-budget                        # Exposes dev-budget.agentictools.uk

database:
  postgres: true

# Optional: Persistent host mounts (isolated from production data)
volumes:
  - /server/data/monthlybudget-dev/uploads:/app/data/uploads
Step 4: Configure Isolated Dev Secrets (Optional)
Because manager.py loads secrets based on the folder name in /server/apps/, create a matching .env file if your app requires environment variables:

Bash
cp /server/secrets/monthlybudget.env /server/secrets/monthlybudget-dev.env
nano /server/secrets/monthlybudget-dev.env
(Update DATABASE_URL or API keys if you want your dev container to use a separate test database).

Step 5: Add the dev Route to Cloudflare Tunnels & Reload Caddy
Go to your Cloudflare Zero Trust Dashboard -> Networks -> Tunnels -> Public Hostname -> Add a public hostname:

Subdomain: dev-budget

Domain: agentictools.uk

Service Type: HTTP

URL: http://caddy-proxy:80

Save the hostname.

On your server, wait 30 seconds for manager.py to generate /server/caddy/sites/monthlybudget-dev.caddy, then reload Caddy if auto-reload is not enabled:

Bash
docker restart caddy-proxy
Step 6: The Day-to-Day GitOps Workflow
Once both folders are active on the server, your pipeline is completely hands-free:

Experimenting: Commit and push code to the dev branch. Within ~90 seconds, GitHub Actions builds :dev and manager.py updates https://dev-budget.agentictools.uk. Production remains untouched.

Releasing to Production: Open a Pull Request on GitHub and merge dev into main. GitHub Actions builds :main and manager.py automatically rolls out the verified build to https://budget.agentictools.uk.


---

### Optional Cleanup for Step 2 of Your Original Guide
In your original guide, **Step 2** instructs you to run `git clone` inside `/server/apps`. If you want the entire document to reflect your cleaner "config-only" architecture, replace **Step 2** in the original section with this:

```markdown
### Step 2: Create the App Folder on Your Server (Config-Only)
Your Homeserver Deployment Manager constantly watches the `/server/apps` directory for `deploy.yml` files. Because GitHub Actions compiles the code into a self-contained Docker image, you **do not** need to clone your source code onto the server—you only need a folder for the deployment contract.

SSH into your server and run:
mkdir -p /server/apps/monthlybudget
cd /server/apps/monthlybudget
nano deploy.yml
