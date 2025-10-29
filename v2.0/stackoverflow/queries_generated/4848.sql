-- {"query": "4848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1159} 
WITH PostEditHistory AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS EditDate,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostLatestEdits AS (
    SELECT
        PostId,
        EditorDisplayName,
        HistoryTypeName,
        EditDate,
        EditComment
    FROM PostEditHistory
    WHERE rn = 1
),
UserPostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate AS PostLastActivityDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.Score) AS MaxScore,
        AVG(p.Score) AS AvgScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id,
        p.OwnerUserId,
        u.DisplayName,
        p.PostTypeId,
        pt.Name,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.CommunityOwnedDate
)
SELECT
    upi.PostId,
    upi.PostTypeName,
    upi.Title,
    upi.OwnerDisplayName,
    upi.PostCreationDate,
    upi.PostLastActivityDate,
    upi.CommentCount,
    upi.UpVoteCount,
    upi.DownVoteCount,
    upi.MaxScore,
    upi.AvgScore,
    upi.IsClosed,
    upi.IsCommunityOwned,
    ple.EditorDisplayName AS LastEditorDisplayName,
    ple.HistoryTypeName AS LastEditType,
    ple.EditDate AS LastEditDate,
    ple.EditComment AS LastEditComment,
    CASE
        WHEN (upi.UpVoteCount + upi.DownVoteCount) > 100 THEN 'High Interaction'
        WHEN upi.CommentCount > 50 THEN 'Highly Discussed'
        ELSE 'Standard'
    END AS InteractionCategory,
    CASE
        WHEN upi.PostLastActivityDate > upi.PostCreationDate + INTERVAL '30 days' AND upi.IsClosed = 0 THEN 'Active Recent'
        WHEN upi.IsClosed = 1 THEN 'Closed'
        ELSE 'Inactive or Archived'
    END AS PostStatus,
    COALESCE(upi.OwnerDisplayName, 'Community') AS EffectiveOwner,
    CASE
        WHEN upi.OwnerUserId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = upi.OwnerUserId AND b.Name LIKE '%Expert%' AND b.Class = 1
        ) THEN 'Gold Expert'
        WHEN upi.OwnerUserId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = upi.OwnerUserId AND b.Name LIKE '%Enthusiast%' AND b.Class = 2
        ) THEN 'Silver Enthusiast'
        ELSE 'No Specific Badge'
    END AS OwnerBadgeStatus,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = upi.PostId AND pl.LinkTypeId = 1) AS LinkedPostCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = upi.PostId AND pl.LinkTypeId = 3) AS DuplicateToCount
FROM UserPostInteraction upi
LEFT JOIN PostLatestEdits ple ON upi.PostId = ple.PostId
WHERE upi.PostCreationDate >= '2023-01-01'
ORDER BY upi.PostLastActivityDate DESC
LIMIT 1000;