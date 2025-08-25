# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RAGFlow is an open-source RAG (Retrieval-Augmented Generation) engine based on deep document understanding. It offers a streamlined workflow for businesses to build AI-powered question-answering systems with citations from complex formatted data.

## Tech Stack

### Backend
- **Python 3.10-3.12** - Core backend language
- **Flask** - Web framework
- **Elasticsearch/OpenSearch** - Document indexing and search
- **Multiple LLM integrations** - OpenAI, Anthropic, Cohere, and many others
- **Peewee** - ORM for database operations
- **Valkey (Redis)** - Caching and distributed locks

### Frontend  
- **React 18** with TypeScript
- **Umi Framework** - Build framework
- **Ant Design** - UI components
- **Tailwind CSS** - Styling
- **Monaco Editor** - Code editing

### Infrastructure
- **Docker & Docker Compose** - Containerization
- **MinIO** - S3-compatible object storage
- **PostgreSQL/MySQL** - Primary database

## Key Directories

- `/api/` - Flask REST API implementation, authentication, and web services
- `/rag/` - Core RAG engine, retrieval algorithms, and LLM integrations
- `/deepdoc/` - Document parsing, OCR, and deep understanding modules
- `/web/` - React frontend application
- `/agent/` - Agentic workflow and function calling implementations
- `/graphrag/` - Graph-based RAG components
- `/sandbox/` - Sandboxed code execution environment
- `/docker/` - Docker configurations and compose files
- `/test/` - Test suites for API and SDK

## Development Commands

### Backend Development

```bash
# Install dependencies with uv
uv sync --python 3.10 --all-extras
uv run download_deps.py

# Launch dependent services (Elasticsearch, Redis, MinIO, etc.)
docker compose -f docker/docker-compose-base.yml up -d

# Run backend server
source .venv/bin/activate
export PYTHONPATH=$(pwd)
bash docker/launch_backend_service.sh
```

### Frontend Development

```bash
cd web
npm install
npm run dev         # Start development server
npm run build       # Build for production
npm run lint        # Run ESLint
```

### Testing

```bash
# Run Python tests
pytest test/

# Run specific test categories
pytest test/ -m "p1"  # High priority tests
pytest test/ -m "p2"  # Medium priority tests
```

### Docker Deployment

```bash
cd docker
docker compose up -d
```

## Architecture Overview

RAGFlow follows a microservices architecture with clear separation of concerns:

1. **API Layer** (`/api/`) - Handles HTTP requests, authentication, and routing through Flask. Key entry point is `api/ragflow_server.py`.

2. **RAG Engine** (`/rag/`) - Core retrieval and generation logic. Manages:
   - Document chunking strategies
   - Embedding generation and vector search
   - LLM interactions and prompt management
   - Retrieval algorithms and ranking

3. **Document Processing** (`/deepdoc/`) - Sophisticated document understanding:
   - Multi-format parsing (PDF, DOCX, Excel, PPT, etc.)
   - OCR and layout analysis
   - Table and figure extraction
   - Semantic chunking based on document structure

4. **Agent System** (`/agent/`) - Orchestrates complex workflows:
   - Function calling and tool use
   - Multi-step reasoning
   - Internet search integration
   - Code execution in sandboxed environment

5. **Task Queue System** - Asynchronous processing:
   - Document parsing tasks handled by `rag/svr/task_executor.py`
   - Multiple worker processes configured via `WS` environment variable
   - Redis-based task queue and distributed locking

## Key Patterns and Conventions

### Database Models
- Uses Peewee ORM with models defined in `/api/db/db_models.py`
- Service layer pattern in `/api/db/services/`
- Database migrations handled via `docker/migration.sh`

### API Structure
- RESTful endpoints organized by resource in `/api/apps/`
- Authentication via API keys or session tokens
- Consistent error handling and response formats

### Frontend Components
- Components organized by feature in `/web/src/pages/`
- Shared components in `/web/src/components/`
- API client services in `/web/src/services/`
- State management using Umi's built-in capabilities

### Configuration
- Environment variables loaded from `.env` files
- Settings modules: `api/settings.py` and `rag/settings.py`
- Docker environment configurations in `/docker/.env`

## Important Notes

- The system requires significant resources: 4+ CPU cores, 16+ GB RAM, 50+ GB disk
- Multiple embedding models are downloaded on first run via `download_deps.py`
- Document processing is CPU/GPU intensive - configure workers appropriately
- Redis is used for distributed locking - ensure proper Redis configuration
- File storage uses MinIO by default - configure S3 credentials if needed