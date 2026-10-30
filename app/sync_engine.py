from datetime import datetime
from sqlalchemy.orm import Session
from . import models, schemas

def process_sync_batch(db: Session, sync_req: schemas.SyncRequest) -> schemas.SyncResponse:
    applied = 0
    conflicts = []

    for change in sync_req.changes:
        if change.entity_type == "project":
            proj = db.query(models.Project).filter(models.Project.id == change.entity_id).first()
            
            if change.action == "create":
                if not proj:
                    new_proj = models.Project(
                        id=change.entity_id,
                        folder_id=change.payload.get("folder_id"),
                        title=change.payload.get("title", "Untitled Project"),
                        current_state=change.payload.get("current_state", ""),
                        status=change.payload.get("status", "active"),
                        version=1
                    )
                    db.add(new_proj)
                    applied += 1
            elif change.action == "update":
                if proj:
                    # Check version conflict
                    if change.base_version is not None and change.base_version < proj.version:
                        # Inspect field collisions
                        field_conflicts = []
                        server_data = {
                            "title": proj.title,
                            "current_state": proj.current_state,
                            "status": proj.status,
                            "folder_id": proj.folder_id
                        }
                        
                        for k, v in change.payload.items():
                            if k in server_data and server_data[k] != v:
                                field_conflicts.append(k)

                        if field_conflicts:
                            # Staged conflict detected: do not overwrite, flag to user
                            conflicts.append(schemas.ConflictItem(
                                entity_type="project",
                                entity_id=proj.id,
                                field_conflicts=field_conflicts,
                                client_payload=change.payload,
                                server_payload=server_data,
                                server_version=proj.version
                            ))
                            continue
                        else:
                            # Auto-merge non-conflicting updates
                            for k, v in change.payload.items():
                                if hasattr(proj, k):
                                    setattr(proj, k, v)
                            proj.version += 1
                            applied += 1
                    else:
                        # Clean update
                        for k, v in change.payload.items():
                            if hasattr(proj, k):
                                setattr(proj, k, v)
                        proj.version += 1
                        applied += 1
            elif change.action == "delete":
                if proj:
                    db.delete(proj)
                    applied += 1

        elif change.entity_type == "milestone":
            milestone = db.query(models.Milestone).filter(models.Milestone.id == change.entity_id).first()

            if change.action == "create":
                if not milestone:
                    new_m = models.Milestone(
                        id=change.entity_id,
                        project_id=change.payload.get("project_id"),
                        title=change.payload.get("title", ""),
                        is_completed=change.payload.get("is_completed", False),
                        completed_at=datetime.utcnow() if change.payload.get("is_completed") else None,
                        order=change.payload.get("order", 0),
                        version=1
                    )
                    db.add(new_m)
                    applied += 1
            elif change.action == "update":
                if milestone:
                    for k, v in change.payload.items():
                        if k == "is_completed":
                            is_comp = v if isinstance(v, bool) else (str(v).lower() in ("true", "1"))
                            milestone.is_completed = is_comp
                            milestone.completed_at = datetime.utcnow() if is_comp else None
                        elif hasattr(milestone, k):
                            setattr(milestone, k, v)
                    milestone.version += 1
                    applied += 1
            elif change.action == "delete":
                if milestone:
                    db.delete(milestone)
                    applied += 1

    db.commit()

    # Collect server state modified since client's last sync
    server_changes = {}
    if sync_req.since:
        updated_projects = db.query(models.Project).filter(models.Project.updated_at > sync_req.since).all()
        server_changes["projects"] = [
            {"id": p.id, "title": p.title, "current_state": p.current_state, "status": p.status, "version": p.version, "updated_at": p.updated_at.isoformat()}
            for p in updated_projects
        ]
        updated_milestones = db.query(models.Milestone).filter(models.Milestone.updated_at > sync_req.since).all()
        server_changes["milestones"] = [
            {"id": m.id, "project_id": m.project_id, "title": m.title, "is_completed": m.is_completed, "completed_at": m.completed_at.isoformat() if m.completed_at else None, "version": m.version}
            for m in updated_milestones
        ]

    return schemas.SyncResponse(
        success=True,
        applied_count=applied,
        conflicts=conflicts,
        server_changes=server_changes
    )
