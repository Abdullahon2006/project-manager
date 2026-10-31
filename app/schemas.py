from datetime import datetime
from typing import List, Optional, Any
from pydantic import BaseModel, Field

# --- Milestone Schemas ---
class MilestoneBase(BaseModel):
    title: str
    is_completed: bool = False
    completed_at: Optional[datetime] = None
    order: int = 0

class MilestoneCreate(MilestoneBase):
    id: Optional[str] = None

class MilestoneUpdate(BaseModel):
    title: Optional[str] = None
    is_completed: Optional[bool] = None
    completed_at: Optional[datetime] = None
    order: Optional[int] = None
    version: Optional[int] = None

class MilestoneOut(MilestoneBase):
    id: str
    project_id: str
    version: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# --- Project Schemas ---
class ProjectBase(BaseModel):
    title: str
    current_state: str = ""
    status: str = "active"

class ProjectCreate(ProjectBase):
    id: Optional[str] = None
    folder_id: str

class ProjectUpdate(BaseModel):
    title: Optional[str] = None
    current_state: Optional[str] = None
    status: Optional[str] = None
    folder_id: Optional[str] = None
    version: Optional[int] = None

class ProjectSummary(BaseModel):
    id: str
    folder_id: str
    title: str
    status: str
    version: int
    next_action: Optional[str] = None
    updated_at: datetime

class ProjectDetailOut(ProjectBase):
    id: str
    folder_id: str
    version: int
    created_at: datetime
    updated_at: datetime
    active_milestones: List[MilestoneOut] = []
    archived_milestones: List[MilestoneOut] = []
    archived_count: int = 0
    archived_preview: List[MilestoneOut] = []

    class Config:
        from_attributes = True

# --- Folder Schemas (Bento View) ---
class FolderBase(BaseModel):
    name: str
    icon: str = "📁"
    color: str = "#3b82f6"
    order: int = 0

class FolderCreate(FolderBase):
    id: Optional[str] = None

class FolderUpdate(BaseModel):
    name: Optional[str] = None
    icon: Optional[str] = None
    color: Optional[str] = None
    order: Optional[int] = None

class FolderBentoOut(FolderBase):
    id: str
    created_at: datetime
    updated_at: datetime
    project_count: int = 0
    recent_projects: List[ProjectSummary] = []

    class Config:
        from_attributes = True

# --- Staged Sync Engine Schemas ---
class StagedChange(BaseModel):
    id: Optional[str] = None
    entity_type: str # "folder", "project", "milestone"
    entity_id: str
    action: str      # "create", "update", "delete"
    base_version: Optional[int] = None
    payload: dict    # Fields changed
    client_timestamp: datetime = Field(default_factory=datetime.utcnow)

class SyncRequest(BaseModel):
    client_id: str
    changes: List[StagedChange] = []
    since: Optional[datetime] = None

class ConflictItem(BaseModel):
    entity_type: str
    entity_id: str
    field_conflicts: List[str]
    client_payload: dict
    server_payload: dict
    server_version: int

class SyncResponse(BaseModel):
    success: bool
    applied_count: int
    conflicts: List[ConflictItem] = []
    server_changes: dict = {}
    server_time: datetime = Field(default_factory=datetime.utcnow)
