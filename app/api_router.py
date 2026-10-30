from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from . import models, schemas, sync_engine
from .database import get_db

api_router = APIRouter(prefix="/api", tags=["Application API"])

# --- Bento Home Screen ---
@api_router.get("/bento", response_model=List[schemas.FolderBentoOut])
def get_bento_dashboard(db: Session = Depends(get_db)):
    """Returns Bento box cards for each folder, including recent project previews and next actions."""
    folders = db.query(models.Folder).order_by(models.Folder.order).all()
    bento_results = []

    for folder in folders:
        projects = db.query(models.Project).filter(
            models.Project.folder_id == folder.id
        ).order_by(models.Project.updated_at.desc()).all()

        recent_summaries = []
        for p in projects[:3]: # top 3 recent projects for bento card preview
            next_m = db.query(models.Milestone).filter(
                models.Milestone.project_id == p.id,
                models.Milestone.is_completed == False
            ).order_by(models.Milestone.order).first()

            recent_summaries.append(schemas.ProjectSummary(
                id=p.id,
                folder_id=p.folder_id,
                title=p.title,
                status=p.status,
                version=p.version,
                next_action=next_m.title if next_m else None,
                updated_at=p.updated_at
            ))

        bento_results.append(schemas.FolderBentoOut(
            id=folder.id,
            name=folder.name,
            icon=folder.icon,
            color=folder.color,
            order=folder.order,
            created_at=folder.created_at,
            updated_at=folder.updated_at,
            project_count=len(projects),
            recent_projects=recent_summaries
        ))

    return bento_results

# --- Folders ---
@api_router.post("/folders", response_model=schemas.FolderBentoOut)
def create_folder(payload: schemas.FolderCreate, db: Session = Depends(get_db)):
    folder = models.Folder(
        name=payload.name,
        icon=payload.icon,
        color=payload.color,
        order=payload.order
    )
    if payload.id:
        folder.id = payload.id
    db.add(folder)
    db.commit()
    db.refresh(folder)
    return schemas.FolderBentoOut(
        id=folder.id,
        name=folder.name,
        icon=folder.icon,
        color=folder.color,
        order=folder.order,
        created_at=folder.created_at,
        updated_at=folder.updated_at,
        project_count=0,
        recent_projects=[]
    )

@api_router.patch("/folders/{folder_id}")
def update_folder(folder_id: str, payload: schemas.FolderUpdate, db: Session = Depends(get_db)):
    folder = db.query(models.Folder).filter(models.Folder.id == folder_id).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")
    for k, v in payload.dict(exclude_unset=True).items():
        setattr(folder, k, v)
    db.commit()
    db.refresh(folder)
    return {"status": "ok", "id": folder.id}

@api_router.delete("/folders/{folder_id}")
def delete_folder(folder_id: str, db: Session = Depends(get_db)):
    folder = db.query(models.Folder).filter(models.Folder.id == folder_id).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")
    db.delete(folder)
    db.commit()
    return {"status": "ok", "deleted_id": folder_id}

# --- Projects ---
@api_router.get("/folders/{folder_id}/projects", response_model=List[schemas.ProjectSummary])
def get_folder_projects(folder_id: str, db: Session = Depends(get_db)):
    projects = db.query(models.Project).filter(
        models.Project.folder_id == folder_id
    ).order_by(models.Project.updated_at.desc()).all()

    summaries = []
    for p in projects:
        next_m = db.query(models.Milestone).filter(
            models.Milestone.project_id == p.id,
            models.Milestone.is_completed == False
        ).order_by(models.Milestone.order).first()

        summaries.append(schemas.ProjectSummary(
            id=p.id,
            folder_id=p.folder_id,
            title=p.title,
            status=p.status,
            version=p.version,
            next_action=next_m.title if next_m else None,
            updated_at=p.updated_at
        ))
    return summaries

@api_router.get("/projects", response_model=List[schemas.ProjectSummary])
def list_projects(status: Optional[str] = None, folder_id: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(models.Project)
    if status:
        q = q.filter(models.Project.status == status)
    if folder_id:
        q = q.filter(models.Project.folder_id == folder_id)
    projects = q.order_by(models.Project.updated_at.desc()).all()

    summaries = []
    for p in projects:
        next_m = db.query(models.Milestone).filter(
            models.Milestone.project_id == p.id,
            models.Milestone.is_completed == False
        ).order_by(models.Milestone.order).first()

        summaries.append(schemas.ProjectSummary(
            id=p.id,
            folder_id=p.folder_id,
            title=p.title,
            status=p.status,
            version=p.version,
            next_action=next_m.title if next_m else None,
            updated_at=p.updated_at
        ))
    return summaries

@api_router.get("/projects/{project_id}", response_model=schemas.ProjectDetailOut)
def get_project_detail(project_id: str, db: Session = Depends(get_db)):
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found")

    active = db.query(models.Milestone).filter(
        models.Milestone.project_id == project_id,
        models.Milestone.is_completed == False
    ).order_by(models.Milestone.order).all()

    archived = db.query(models.Milestone).filter(
        models.Milestone.project_id == project_id,
        models.Milestone.is_completed == True
    ).order_by(models.Milestone.completed_at.desc()).all()

    return schemas.ProjectDetailOut(
        id=proj.id,
        folder_id=proj.folder_id,
        title=proj.title,
        current_state=proj.current_state,
        status=proj.status,
        version=proj.version,
        created_at=proj.created_at,
        updated_at=proj.updated_at,
        active_milestones=active,
        archived_milestones=archived,
        archived_count=len(archived),
        archived_preview=archived[:2]
    )

@api_router.post("/projects", response_model=schemas.ProjectDetailOut)
def create_project(payload: schemas.ProjectCreate, db: Session = Depends(get_db)):
    proj = models.Project(
        folder_id=payload.folder_id,
        title=payload.title,
        current_state=payload.current_state,
        status=payload.status,
        version=1
    )
    if payload.id:
        proj.id = payload.id
    db.add(proj)
    db.commit()
    db.refresh(proj)
    return schemas.ProjectDetailOut(
        id=proj.id,
        folder_id=proj.folder_id,
        title=proj.title,
        current_state=proj.current_state,
        status=proj.status,
        version=proj.version,
        created_at=proj.created_at,
        updated_at=proj.updated_at,
        active_milestones=[],
        archived_milestones=[],
        archived_count=0,
        archived_preview=[]
    )

@api_router.patch("/projects/{project_id}")
def update_project(project_id: str, payload: schemas.ProjectUpdate, db: Session = Depends(get_db)):
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found")

    for k, v in payload.dict(exclude_unset=True).items():
        if k != "version":
            setattr(proj, k, v)
    proj.version += 1
    db.commit()
    db.refresh(proj)
    return {"status": "ok", "version": proj.version}

# --- Milestones ---
@api_router.post("/milestones", response_model=schemas.MilestoneOut)
def create_milestone(payload: schemas.MilestoneCreate, project_id: str = Query(...), db: Session = Depends(get_db)):
    m = models.Milestone(
        project_id=project_id,
        title=payload.title,
        is_completed=payload.is_completed,
        completed_at=datetime.utcnow() if payload.is_completed else None,
        order=payload.order,
        version=1
    )
    if payload.id:
        m.id = payload.id
    db.add(m)
    
    # Bump project version
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if proj:
        proj.version += 1

    db.commit()
    db.refresh(m)
    return m

@api_router.patch("/milestones/{milestone_id}")
def update_milestone(milestone_id: str, payload: schemas.MilestoneUpdate, db: Session = Depends(get_db)):
    m = db.query(models.Milestone).filter(models.Milestone.id == milestone_id).first()
    if not m:
        raise HTTPException(status_code=404, detail="Milestone not found")

    for k, v in payload.dict(exclude_unset=True).items():
        if k == "is_completed":
            m.is_completed = v
            m.completed_at = datetime.utcnow() if v else None
        elif k != "version":
            setattr(m, k, v)
    m.version += 1
    if m.project:
        m.project.version += 1
    db.commit()
    return {"status": "ok", "version": m.version, "completed_at": m.completed_at.isoformat() if m.completed_at else None}

@api_router.delete("/milestones/{milestone_id}")
def delete_milestone(milestone_id: str, db: Session = Depends(get_db)):
    m = db.query(models.Milestone).filter(models.Milestone.id == milestone_id).first()
    if not m:
        raise HTTPException(status_code=404, detail="Milestone not found")
    proj = m.project
    if proj:
        proj.version += 1
    db.delete(m)
    db.commit()
    return {"status": "ok", "deleted_id": milestone_id}

@api_router.delete("/projects/{project_id}")
def delete_project(project_id: str, db: Session = Depends(get_db)):
    proj = db.query(models.Project).filter(models.Project.id == project_id).first()
    if not proj:
        raise HTTPException(status_code=404, detail="Project not found")
    db.query(models.Milestone).filter(models.Milestone.project_id == project_id).delete()
    db.delete(proj)
    db.commit()
    return {"status": "ok", "deleted_id": project_id}

# --- Staged Sync Endpoint ---
@api_router.post("/sync", response_model=schemas.SyncResponse)
def sync_data(req: schemas.SyncRequest, db: Session = Depends(get_db)):
    """Receives staged client changes, checks versions/conflicts, and responds with merged server updates."""
    return sync_engine.process_sync_batch(db, req)
