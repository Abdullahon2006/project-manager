import os
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from .database import engine, Base, SessionLocal
from .models import Folder, Project, Milestone
from .api_router import api_router
from .agent_router import agent_router

# Initialize database tables
Base.metadata.create_all(bind=engine)

def seed_default_data():
    db = SessionLocal()
    try:
        if db.query(Folder).count() == 0:
            f1 = Folder(name="Coding", icon="⚡", color="#3b82f6", order=1)
            f2 = Folder(name="Creative", icon="🎨", color="#8b5cf6", order=2)
            f3 = Folder(name="Life", icon="🌱", color="#10b981", order=3)
            db.add_all([f1, f2, f3])
            db.commit()

        # Ensure sample projects exist so workspace is never empty
        if db.query(Project).count() == 0:
            f1 = db.query(Folder).order_by(Folder.order).first()
            if f1:
                p1 = Project(
                    folder_id=f1.id,
                    title="State & Next Monorepo",
                    current_state="FastAPI backend setup complete. Structuring SwiftUI views for iOS and Tauri desktop app.",
                    status="active"
                )
                db.add(p1)
                db.commit()

                m1 = Milestone(project_id=p1.id, title="Compile SwiftUI Xcode project", is_completed=False, order=1)
                m2 = Milestone(project_id=p1.id, title="Test staged conflict resolution modal", is_completed=False, order=2)
                m_archived = Milestone(project_id=p1.id, title="Design Bento UI and Sync Engine architecture", is_completed=True, completed_at=p1.created_at, order=0)
                db.add_all([m1, m2, m_archived])
                db.commit()
    finally:
        db.close()

seed_default_data()

app = FastAPI(
    title="State & Next Backend API",
    version="1.0.0",
    description="Synchronized Backend Engine with Bento Folders, Staged Conflict Resolution, and AI Agent API."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)
app.include_router(agent_router)

STATIC_INDEX = os.path.join(os.path.dirname(__file__), "static", "index.html")

@app.get("/", include_in_schema=False)
def serve_root():
    if os.path.exists(STATIC_INDEX):
        return FileResponse(STATIC_INDEX)
    return {
        "app": "State & Next API",
        "status": "online",
        "docs": "/docs",
        "endpoints": ["/api/bento", "/api/sync", "/api/agent/overview"]
    }

@app.get("/api")
def api_info():
    return {
        "app": "State & Next API",
        "status": "online",
        "docs": "/docs",
        "endpoints": ["/api/bento", "/api/sync", "/api/agent/overview"]
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}
