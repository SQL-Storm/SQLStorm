WITH RecursiveCloseEvents AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        CAST(ph.Comment AS INTEGER) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
),
valid AS (
    SELECT DISTINCT
        PostId,
        MIN(CreationDate) OVER (PARTITION BY PostId) AS CloseEventFinding
    FROM RecursiveCloseEvents
)
SELECT
    PostId,
    CloseEventFinding
FROM valid;