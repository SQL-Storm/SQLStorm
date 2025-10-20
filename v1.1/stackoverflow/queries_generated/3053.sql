-- {"query": "3053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 908} 
WITH RecentComments AS (
    SELECT c.PostId, c.Id AS CommentId, c.UserId, c.CreationDate
    FROM Comments c
    WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
),
PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.ContentLicense,
        u.Reputation,
        u.Location,
        u.LastAccessDate,
        bt.Name AS PostHistoryType,
        ph.CreationDate AS LastEditDate,
        ph.UserId AS LastEditorId,
        ph.UserDisplayName AS LastEditorName,
        ph.Comment AS LastEditComment,
        ARRAY_AGG(DISTINCT tl.Name) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedTags,
        ARRAY_AGG(DISTINCT cc.CommentId) AS RecentCommentIds
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
        AND ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,22,24,25,31,33,34,35,36,37,38,50,52,53,66)
        AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate)
            FROM PostHistory ph2
            WHERE ph2.PostId = p.Id
        )
    LEFT JOIN PostHistoryType bt ON ph.PostHistoryTypeId = bt.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
        AND pl.LinkTypeId = 1
    LEFT JOIN RecentComments cc ON p.Id = cc.PostId
    GROUP BY p.Id, u.Reputation, u.Location, u.LastAccessDate, bt.Name, ph.CreationDate, ph.UserId, ph.UserDisplayName, ph.Comment
)
SELECT
    ps.PostId,
    ps.PostTypeId,
    ps.Title,
    ps.Tags,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.OwnerUserId,
    ps.Reputation,
    ps.Location,
    ps.LastAccessDate,
    ps.PostHistoryType,
    ps.LastEditDate,
    ps.LastEditorId,
    ps.LastEditorName,
    ps.LastEditComment,
    ps.LinkedTags,
    ps.RecentCommentIds,
    CASE WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 5 THEN 'Popular Question' ELSE 'Standard' END AS PostCategory,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = ps.PostId AND v2.VoteTypeId = 8) AS AverageBounty
FROM PostStats ps
WHERE
    (ps.Score > 0 OR ps.ViewCount > 100)
    AND ps.OwnerUserId IS NOT NULL
    AND (ps.LastAccessDate >= NOW() - INTERVAL '90 days')
    AND (ps.PostTypeId IN (1, 2))
    AND (EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Name ILIKE '%teacher%') OR ps.Reputation > 1000)
UNION
SELECT
    NULL,
    NULL,
    'Summary',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
ORDER BY
    PostTypeId NULLS LAST,
    Score DESC
LIMIT 100;