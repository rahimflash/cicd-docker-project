# CLMS

A modern web application built with Laravel backend and Next.js frontend in a monorepo structure.

## Project Structure

This is a monorepo containing two main applications:

```
clms/
├── back-end/           # Laravel API server
├── front-end/          # Next.js web application
├── docker-compose.yml  # Local development setup
└── Jenkinsfile        # CI/CD pipeline
```

**Backend (Laravel 10 + PHP 8.1)**
- RESTful API server
- User authentication and authorization
- Admin Dashboarding
- Database operations with PostgreSQL
- Redis for caching and sessions

**Frontend (Next.js 14 + React 18)**
- Modern React application
- Server-side rendering
- Responsive design with Tailwind CSS
- Real-time updates and notifications

## Getting Started

### Prerequisites

Make sure you have these installed on your machine:
- Docker and Docker Compose
- Git
- Node.js 18+ (for local development)
- PHP 8.1+ (for local development)

### Quick Start with Docker

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd clms
   ```

2. **Set up environment files**
   ```bash
   # Backend environment
   cp back-end/.env.example back-end/.env
   
   # Frontend environment  
   cp front-end/.env.example front-end/.env.local
   
   # Database environment
   cp .env.example .env
   ```

3. **Start the application**
   ```bash
   docker compose up -d
   ```

4. **Access the application**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - Database: PostgreSQL on localhost:5432

### Local Development Setup

If you prefer to run the applications locally without Docker:

**Backend Setup**
```bash
cd back-end
composer install
php artisan key:generate
php artisan migrate
php artisan serve
```

**Frontend Setup**
```bash
cd front-end
npm install
npm run dev
```

## Environment Configuration

### Backend (.env)
```bash
APP_NAME=CLMS
APP_ENV=local
APP_DEBUG=true
APP_URL=http://localhost:8000

DB_CONNECTION=pgsql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=clms
DB_USERNAME=your_db_user
DB_PASSWORD=your_db_password

REDIS_HOST=localhost
REDIS_PASSWORD=null
REDIS_PORT=6379
```

### Frontend (.env.local)
```bash
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_APP_NAME=CLMS
NODE_ENV=development
```

## Development Workflow

### Making Changes

The project uses an intelligent CI/CD pipeline that only builds components that have changed:

- **Frontend changes only**: Only the Next.js app gets built and deployed
- **Backend changes only**: Only the Laravel API gets built and deployed  
- **Both changed**: Both applications get built and deployed
- **Root-level changes**: Both applications get built (safer approach)

### Running Tests

**Backend Tests**
```bash
cd back-end
php artisan test
```

**Frontend Tests**  
```bash
cd front-end
npm test
npm run lint
```

### Code Quality

The pipeline automatically runs several quality checks:
- PHP syntax validation
- Composer security audit
- NPM security audit
- Secret scanning for exposed credentials
- Docker image vulnerability scanning with Trivy

## CI/CD Pipeline

The Jenkins pipeline provides automated building, testing, and deployment with these features:

### Smart Building
- Detects which parts of the codebase changed
- Only builds affected components
- Saves time and resources on large codebases

### Build Parameters
- **BUILD_TYPE**: Choose development, staging, or production
- **FORCE_BUILD_ALL**: Build everything regardless of changes
- **FORCE_BACKEND_ONLY**: Build only the backend
- **FORCE_FRONTEND_ONLY**: Build only the frontend
- **SKIP_TESTS**: Skip test execution (not recommended)

### Interactive Deployment
After successful builds, the pipeline asks if you want to deploy locally for testing. This prevents unnecessary resource usage while allowing on-demand integration testing.

### Security Features
- Credential masking and secure handling
- Container vulnerability scanning
- Dependency security auditing
- Secret pattern detection

## Deployment

### Local Deployment

The pipeline can deploy to your local Docker environment for testing:
1. Built images replace source code mounts
2. All services start with proper health checks
3. Integration tests verify everything works together

### Production Deployment

Docker images are pushed to Docker Hub and tagged with:
- Build number (e.g., `clms-backend:42`)
- Environment type (e.g., `clms-backend:production`)  
- Latest tag (e.g., `clms-backend:latest`)

## Architecture

### Backend Architecture
- **Framework**: Laravel 10 with PHP 8.1
- **Database**: PostgreSQL 15 with optimized queries
- **Caching**: Redis for session and application caching
- **Authentication**: Laravel Sanctum for API tokens
- **Testing**: PHPUnit with feature and unit tests

### Frontend Architecture  
- **Framework**: Next.js 14 with React 18
- **Styling**: Tailwind CSS for responsive design
- **State Management**: React Context and custom hooks
- **API Integration**: Fetch API with custom service layer
- **Testing**: Jest and React Testing Library

### Infrastructure
- **Containerization**: Docker with multi-stage builds
- **Networking**: Host networking for local development
- **Persistence**: Named volumes for database and Redis data
- **Health Checks**: Built-in health monitoring for all services

## Database

### Running Migrations
```bash
# Inside backend container or local environment
php artisan migrate
```

### Seeding Data
```bash
php artisan db:seed
```

### Database Design
The application uses PostgreSQL with these main entities:
- Users (users, roles, admins)

## API Documentation

The Laravel backend provides RESTful APIs for:

### Authentication
- `POST /api/login` - User login
- `POST /api/logout` - User logout  
- `POST /api/register` - New user registration

## Troubleshooting

### Common Issues

**Database Connection Failed**
```bash
# Check if PostgreSQL is running
docker compose ps
# Restart database service
docker compose restart database
```

**Frontend Build Errors**
```bash
# Clear Next.js cache
cd front-end
rm -rf .next
npm run build
```

**Port Conflicts**
```bash
# Check what's using the ports
lsof -i :3000
lsof -i :8000
lsof -i :5432
```

**Container Health Check Failures**
```bash
# Check container logs
docker compose logs backend
docker compose logs frontend
docker compose logs database
```

### Pipeline Issues

**Change Detection Not Working**
The pipeline falls back to building all components if change detection fails, ensuring nothing is missed.

**Build Failures**
Check the Jenkins console output for specific error messages. Common issues:
- Missing environment variables
- Docker registry authentication
- Test failures
- Security scan failures

## Contributing

### Development Guidelines

1. **Branching**: Use feature branches off `main`
2. **Commits**: Write clear, descriptive commit messages
3. **Testing**: Add tests for new features
4. **Code Style**: Follow existing patterns and formatting
5. **Documentation**: Update README when adding features

### Pull Request Process

1. Create feature branch from `main`
2. Make your changes with appropriate tests
3. Run quality checks locally
4. Submit pull request with clear description
5. Address feedback from code review

### Code Standards

**Backend (PHP)**
- Follow PSR-12 coding standards
- Use type hints and return types
- Write feature tests for new endpoints
- Document complex business logic

**Frontend (JavaScript/React)**
- Use ESLint and Prettier configurations
- Write component tests for new features
- Follow React best practices
- Use TypeScript where beneficial

## Performance

### Optimization Features

**Backend Performance**
- Database query optimization with eager loading
- Redis caching for frequently accessed data
- API response caching
- Background job processing

**Frontend Performance**
- Next.js automatic code splitting
- Image optimization with Next.js Image component
- Static generation where appropriate
- Bundle size monitoring

## Security

### Security Measures

**Application Security**
- Input validation and sanitization
- SQL injection prevention with ORM
- XSS protection with proper escaping
- CSRF protection with Laravel tokens

**Infrastructure Security**
- Container security scanning
- Dependency vulnerability monitoring  
- Secret management best practices
- Regular security updates

## Support

### Getting Help

- **Documentation**: Check this README first
- **Issues**: Create GitHub issues for bugs
- **Questions**: Use GitHub discussions
- **Security**: Email security issues privately

### Monitoring

The application includes basic monitoring:
- Health check endpoints for all services
- Error logging and reporting
- Performance metrics collection
- Database query monitoring

## Changelog

### Recent Updates
- Implemented smart CI/CD pipeline with change detection
- Added comprehensive security scanning
- Improved Docker container architecture
- Enhanced error handling and logging
- Added interactive deployment features