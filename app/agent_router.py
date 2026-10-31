import os
import secrets
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.orm import Session
from . import models, schemas
from .database import get_db

agent_router = APIRouter(prefix="/api/agent", tags=["Agent Integration"])

AGENT_KEY = os.getenv("AGENT_API_KEY")

def verify_agent_token(x_agent_key: Optional[str] = Header(None)):
    if not AGENT_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Agent API is disabled: AGENT_API_KEY environment variable is not configured on the server."
        )
    if not x_agent_key or not secrets.compare_digest(x_agent_key, AGENT_KEY):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing X-Agent-Key header."
        )
    return True

@agent_router.get("/overview")
def get_agent_overview(
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_agent_token)
):
    """Provides a high-level briefing of all folders, active projects, and next actions for AI agents."""
    folders = db.query(models.Folder).order_by(models.Folder.order).all()
    overview = []

    for folder in folders:
        active_projects = db.query(models.Project).filter(
            models.Project.folder_id == folder.id,
            models.Project.status == "active"
        ).order_by(models.Project.updated_at.desc()).all()

        project_list = []
        for p in active_projects:
            next_m = db.query(models.Milestone).filter(
                models.Milestone.project_id == p.id,
                models.Milestone.is_completed == False
            ).order_by(models.Milestone.order).first()

            project_list.append({
                "id": p.id,
                "title": p.title,
                "current_state": p.current_state,
                "next_action": next_m.title if next_m else None,
                "next_action_id": next_m.id if next_m else None,
                "version": p.version,
                "updated_at": p.updated_at.isoformat()
            })

        overview.append({
            "folder_id": folder.id,
            "folder_name": folder.name,
            "icon": folder.icon,
            "active_projects": project_list
        })

    return {"status": "ok", "folders": overview}

@agent_router.get("/projects/{project_id}")
def get_agent_project_detail(
    project_id: str,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_agent_token)
):
    """Get full details of a project, active milestones, and packed archive preview for agents."""
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found.")

    active = db.query(models.Milestone).filter(
        models.Milestone.project_id == project_id,
        models.Milestone.is_completed == False
    ).order_by(models.Milestone.order).all()

    archived = db.query(models.Milestone).filter(
        models.Milestone.project_id == project_id,
        models.Milestone.is_completed == True
    ).order_by(models.Milestone.completed_at.desc()).all()

    return {
        "id": proj.id,
        "title": proj.title,
        "current_state": proj.current_state,
        "status": proj.status,
        "version": proj.version,
        "active_milestones": [{"id": m.id, "title": m.title, "order": m.order} for m in active],
        "archived_count": len(archived),
        "archived_preview": [{"id": m.id, "title": m.title, "completed_at": m.completed_at.isoformat()} for m in archived[:2]]
    }

@agent_router.post("/projects/{project_id}/milestones")
def add_agent_milestone(
    project_id: str,
    payload: schemas.MilestoneCreate,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_agent_token)
):
    """Add a new milestone/action to a project via Agent."""
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found.")

    new_m = models.Milestone(
        project_id=project_id,
        title=payload.title,
        is_completed=False,
        order=payload.order or 0
    )
    db.add(new_m)
    proj.version += 1
    db.commit()
    db.refresh(new_m)
    return {"status": "created", "milestone_id": new_m.id, "title": new_m.title}

@agent_router.patch("/milestones/{milestone_id}/complete")
def complete_agent_milestone(
    milestone_id: str,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_agent_token)
):
    """Check off a milestone: timestamps it and packs it into the archive."""
    m = db.query(models.Milestone).filter(models.Milestone.id == milestone_id).first()
    if not m:
        raise HTTPException(status_code=404, detail="Milestone not found.")

    m.is_completed = True
    m.completed_at = datetime.utcnow()
    m.version += 1
    
    if m.project:
        m.project.version += 1

    db.commit()
    return {"status": "completed", "completed_at": m.completed_at.isoformat()}

@agent_router.patch("/projects/{project_id}/state")
def update_agent_project_state(
    project_id: str,
    payload: schemas.ProjectUpdate,
    db: Session = Depends(get_db),
    authorized: bool = Depends(verify_agent_token)
):
    """Update current state notes for a project via Agent."""
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found.")

    if payload.current_state is not None:
        proj.current_state = payload.current_state
    if payload.title is not None:
        proj.title = payload.title
    if payload.status is not None:
        proj.status = payload.status

    proj.version += 1
    db.commit()
    return {"status": "updated", "version": proj.version, "current_state": proj.current_state}
