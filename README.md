# Intro
Simple todo list app with login screen and two levels of permisions.  
Two types of user: **USER** and **ADMIN**.  
### USER
- Can add todo list items
- Can toggle items as done/not done
- Cannot deleate items.
- Is not shown link to the opensearch dashboard (however this is superficial, the button is just hidden)
### ADMIN
- Can add todo list items
- Can toggle items as done/not done
- Can deleate items.
- Is given a button to navigate to the opensearch dashboard

# Deploying
### Deploy the stack
1. Make sure docker and docker compose are installed
   ```console
   curl -fsSL https://get.docker.com | sh
   ```
2. Clone this repo
   ```console
   git clone https://github.com/vcqj/deployment.git
   cd deployment
   ```
3. Run docker compose up
   ```console
   docker compose up
   ```
4. Visit [localhost:8080](http://localhost:8080) to view the web app.
5. Login with either:
   * username: **user**, password: **password**
   * username: **admin**, password: **admin**
6. Visit [localhost:8080/dashboards/](http://localhost:8080/dashboards/) to view the logs in the Opensearch Dashboards UI.

# Stack
* Frontend: Vite + React + shadcn/ui + graphql + Tailwind + Typescript
* API: Apollo + Express
* NginX reverse proxy / gateway
* logging/dashboards: Pino + FluentBit + OpenSearch + OpenSearch Dashboards
* Authenication: basic hardcoded password authentication in the API server
* Authorization: JWT via express middleware, both client side and guards on the API endpoints.
* Containerization: Docker + one repo per service (as apposed to a monorepo).
* CI/CD: Github Actions + protected branches, 3 github workflows
  - one to check docker build is successful before allowing merging to main branch
  - one to check all tests passed before allowing merging to main (only implemented in API service repo)
  - one to build image and push to github container repository after merging a PR to main branch
* Misc: A service that runs a bash script to pre-populate the OpenSearch dashboards with some relevent items.

# Use of AI / Full disclusure
I used AI (ChatGPT-5) quite hevily, partly due to time partly as it can pretty much generate a cleaner UI or config file in a couple of seconds/minutes than what would take me maybe an hour. 
Where I used UI:
* Creating the frontend.
* Creating an outline of the GraphQL API server.
* Writing the YAML files for the github actions workflows.
* Writing the NginX config file.
* Wiring up some of the services in the docker compose file.
* Debugging/probably some other bits.

Having said this, I would be confident there is nothing here I couldn't have done without AI with a bit more time.
