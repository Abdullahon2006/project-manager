from datetime import datetime
from typing import List, Optional, Any
from pydantic import BaseModel, Field

# --- Milestone Schemas ---
class MilestoneBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    is_completed: bool = False
    completed_at: Optional[datetime] = None
    order: int = 0

class MilestoneCreate(MilestoneBase):
    id: Optional[str] = Field(None, max_length=100)

class MilestoneUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=500)
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
    title: str = Field(..., min_length=1, max_length=255)
    current_state: str = Field(default="", max_length=50000)
    status: str = Field(default="active", max_length=30)

class ProjectCreate(ProjectBase):
    id: Optional[str] = Field(None, max_length=100)
    folder_id: str = Field(..., max_length=100)

class ProjectUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    current_state: Optional[str] = Field(None, max_length=50000)
    status: Optional[str] = Field(None, max_length=30)
    folder_id: Optional[str] = Field(None, max_length=100)
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
    name: str = Field(..., min_length=1, max_length=100)
    icon: str = Field(default="📁", max_length=50)
    color: str = Field(default="#3b82f6", max_length=50)
    order: int = 0

class FolderCreate(FolderBase):
    id: Optional[str] = Field(None, max_length=100)

class FolderUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    icon: Optional[str] = Field(None, max_length=50)
    color: Optional[str] = Field(None, max_length=50)
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
    id: Optional[str] = Field(None, max_length=100)
    entity_type: str = Field(..., max_length=50) # "folder", "project", "milestone"
    entity_id: str = Field(..., max_length=100)
    action: str = Field(..., max_length=50)      # "create", "update", "delete"
    base_version: Optional[int] = None
    payload: dict = Field(default_factory=dict)
    client_timestamp: datetime = Field(default_factory=datetime.utcnow)

class SyncRequest(BaseModel):
    client_id: str = Field(default="ios_device_app", max_length=100)
    changes: List[StagedChange] = Field(default_factory=list)
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
