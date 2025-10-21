WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
),
LatestEdits AS (
    SELECT
        rph.PostId,
        rph.PostHistoryTypeId,
        rph.CreationDate as LastEditDate,
        rph.UserId as LastEditorUserId
    FROM RankedPostHistory rph
    WHERE rph.rn = 1
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    le.LastEditorUserId,
    le.LastEditDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseCount, -- Count of 'Post Closed' history entries
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11) AS ReopenCount -- Count of 'Post Reopened' history entries
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    LatestEdits le ON p.Id = le.PostId
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= DATE_TRUNC('day', cast('2024-10-01' as date)) - INTERVAL '365 days' -- Posts created in the last year
ORDER BY
    p.Score DESC,
    p.ViewCount DESC
LIMIT 1000;