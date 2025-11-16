# APISIX Gateway - Standalone Configuration

APISIX API Gateway running in standalone mode with file-based YAML configuration. This setup allows for easy route management and version control via Git.

## Architecture

- **APISIX**: Apache API Gateway v3.7.0
- **Mode**: Standalone (file-based configuration)
- **Configuration**: YAML-based routes in `apisix/apisix.yaml`
- **Dashboard**: APISIX Dashboard for visual management
- **Deployment**: Docker Compose

## Deployment

### Prerequisites
- Docker and Docker Compose installed
- SSH access to the gateway VM

### Directory Structure

```
blnk-apisix-gateway/
├── docker-compose.yml          # Service definitions
├── apisix/
│   └── apisix.yaml             # APISIX configuration and routes
├── .gitignore                  # Git ignore rules
└── README.md                   # This file
```

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/Reptilefury/blnk-apisix-gateway.git
   cd blnk-apisix-gateway
   ```

2. **Deploy to VM**
   ```bash
   cd ~/apisix-blnk
   git pull origin main
   docker-compose down
   docker-compose up -d
   ```

3. **Verify deployment**
   ```bash
   # Check container status
   docker-compose ps

   # Test APISIX Admin API (local)
   curl -s http://127.0.0.1:9080/apisix/admin/version \
     -H "X-API-Key: edd1c9f034335f136f87ad84b625c8f1"
   ```

## Port Mappings

| Service | Internal | External | Purpose |
|---------|----------|----------|---------|
| APISIX HTTP | 9080 | 19080 | API Gateway HTTP |
| APISIX HTTPS | 9443 | 19443 | API Gateway HTTPS |
| Dashboard | 9000 | 19000 | Web UI |
| Admin API | 9080 | 19180 | Admin API (via 19080) |

## Routes

### Keycloak Authentication (`/auth/*`)
- **ID**: 20
- **Target**: `keycloak-438091062981.us-central1.run.app:443`
- **Features**:
  - HTTPS upstream
  - Path rewrite: `/auth/(.*)` → `/$1`
  - CORS enabled (all origins)
  - Request ID tracking
  - Header forwarding (X-Forwarded-*)

## Configuration Management

### Adding a New Route

Edit `apisix/apisix.yaml` and add to the `routes:` section:

```yaml
- id: <route-id>
  uri: "<path-pattern>"
  name: "<route-name>"
  priority: 200
  upstream:
    type: roundrobin
    nodes:
      <upstream-host>:<port>: 1
    scheme: https
  plugins:
    # Add plugins as needed
```

### Deploying Changes

```bash
# Commit and push changes
git add apisix/apisix.yaml
git commit -m "Add/update routes"
git push origin main

# Pull on gateway VM and restart
cd ~/apisix-blnk
git pull origin main
docker-compose restart gateway-apisix
```

## API Access

### Admin API (localhost)
```bash
curl http://127.0.0.1:9080/apisix/admin/routes \
  -H "X-API-Key: edd1c9f034335f136f87ad84b625c8f1"
```

### Gateway Access
```bash
# Local
curl http://127.0.0.1:19080/auth/admin/

# External (replace IP)
curl http://<gateway-ip>:19080/auth/admin/
```

## Troubleshooting

### View logs
```bash
# APISIX logs
docker logs gateway-apisix

# Dashboard logs
docker logs gateway-apisix-dashboard
```

### Restart services
```bash
docker-compose restart gateway-apisix
```

### Validate configuration
```bash
# Check if route is loaded
curl http://127.0.0.1:9080/apisix/admin/routes/20 \
  -H "X-API-Key: edd1c9f034335f136f87ad84b625c8f1" | jq
```

## Environment Variables

Edit `docker-compose.yml` to modify:
- `APISIX_STAND_ALONE: "true"` - Enables standalone mode
- `APISIX_API_KEY` - Admin API authentication key

## Documentation

- [APISIX Documentation](https://apisix.apache.org/docs/)
- [APISIX Standalone Mode](https://apisix.apache.org/docs/apisix/next/deployment-modes/#standalone-mode)
- [Docker Compose](https://docs.docker.com/compose/)

## License

This configuration is part of the Blnk infrastructure project.
