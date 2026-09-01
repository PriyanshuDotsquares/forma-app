"""add password reset, notification prefs, locale, and challenges

Revision ID: ad6d3bbe2fa0
Revises: 561d62621de3
Create Date: 2026-09-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from app.db.seed_data import CHALLENGES

# revision identifiers, used by Alembic.
revision: str = 'ad6d3bbe2fa0'
down_revision: Union[str, None] = '561d62621de3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('locale', sa.String(length=8), server_default='en', nullable=False))
    op.add_column('users', sa.Column('password_reset_token_hash', sa.String(length=64), nullable=True))
    op.add_column('users', sa.Column('password_reset_expires_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        'users',
        sa.Column(
            'notification_prefs',
            postgresql.JSONB(astext_type=sa.Text()),
            server_default='{"workout_reminders": true, "achievement_alerts": true, "weekly_summary": true, "challenge_updates": true}',
            nullable=False,
        ),
    )

    op.create_table(
        'challenges',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('key', sa.String(length=64), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('description', sa.String(length=500), nullable=False),
        sa.Column('metric', sa.String(length=32), nullable=False),
        sa.Column('period', sa.String(length=16), nullable=False),
        sa.Column('target_value', sa.Float(), nullable=False),
        sa.Column('icon', sa.String(length=32), nullable=False),
        sa.Column('is_group', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_challenges_key'), 'challenges', ['key'], unique=True)

    op.create_table(
        'user_challenges',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('challenge_id', sa.UUID(), nullable=False),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('period_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('progress_value', sa.Float(), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['challenge_id'], ['challenges.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_user_challenges_user_id'), 'user_challenges', ['user_id'], unique=False)
    op.create_index(op.f('ix_user_challenges_challenge_id'), 'user_challenges', ['challenge_id'], unique=False)

    challenges_table = sa.table(
        'challenges',
        sa.column('id', sa.UUID()),
        sa.column('key', sa.String()),
        sa.column('title', sa.String()),
        sa.column('description', sa.String()),
        sa.column('metric', sa.String()),
        sa.column('period', sa.String()),
        sa.column('target_value', sa.Float()),
        sa.column('icon', sa.String()),
        sa.column('is_group', sa.Boolean()),
        sa.column('is_active', sa.Boolean()),
    )
    op.bulk_insert(challenges_table, CHALLENGES)


def downgrade() -> None:
    op.drop_index(op.f('ix_user_challenges_challenge_id'), table_name='user_challenges')
    op.drop_index(op.f('ix_user_challenges_user_id'), table_name='user_challenges')
    op.drop_table('user_challenges')
    op.drop_index(op.f('ix_challenges_key'), table_name='challenges')
    op.drop_table('challenges')
    op.drop_column('users', 'notification_prefs')
    op.drop_column('users', 'password_reset_expires_at')
    op.drop_column('users', 'password_reset_token_hash')
    op.drop_column('users', 'locale')
