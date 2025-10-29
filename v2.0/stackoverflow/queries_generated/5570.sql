-- {"query": "5570.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1003} 
WITH
-- recent activity per post
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.CommentCount,
        p.FavoriteCount,
        p.Body,
        COALESCE(p.OwnerDisplayName, '') AS OwnerDisplayName,
        p.LastEditorDisplayName,
        p.LastEditDate,
        COALESCE(p.CloseReason, NULL) AS CloseReason
    FROM Posts p
),
-- derive a synthetic CloseReason from PostHistory when available
PostHistoryWithClose AS (
    SELECT
        rh.PostId,
        rh.Text,
        rh.CreationDate AS HistoryDate,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        ph.Comment,
        ph.ContentLicense,
        ph.UserId
    FROM PostHistory ph
    JOIN (
        SELECT PostId, MAX(CreationDate) AS MaxDate
        FROM PostHistory
        GROUP BY PostId
    ) m ON ph.PostId = m.PostId AND ph.CreationDate = m.MaxDate
),
-- correlate posts to tag information and top tags by count
TagInfo AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired
    FROM Tags t
),
-- compute a set of related posts via PostLinks (duplicates and references)
RelatedPosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pl.CreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
-- windowed ranking of users by reputation and recent activity
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ROW_NUMBER() OVER (
            PARTITION BY u.AccountId
            ORDER BY u.Reputation DESC, u.LastAccessDate DESC
        ) AS rn
    FROM Users u
),
-- aggregate: compute composite score with null-safe arithmetic
Composite AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        rp.Body,
        rp.OwnerDisplayName,
        rp.LastEditorDisplayName,
        rp.LastEditDate,
        rp.CommentCount,
        rp.FavoriteCount,
        COALESCE(rp.Score, 0)
        + COALESCE(rp.ViewCount, 0) * 0.01
        + COALESCE(rp.CommentCount, 0) * 0.05
        AS CompositeScore
    FROM RecentActivity rp
),
-- correlated subquery: latest comment by the post owner
LatestOwnerComment AS (
    SELECT
        c.PostId,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        c.UserId AS CommentUserId
    FROM Comments c
    WHERE c.PostId = c.PostId
    ORDER BY c.CreationDate DESC
    LIMIT 1
)
SELECT
    cte.PostId,
    cte.Title,
    cte.PostTypeId,
    pht.Text AS LastPostHistoryText,
    t.TagName,
    t2.TagName AS RelatedTagName,
    ru.DisplayName AS OwnerDisplayName,
    ru.Reputation AS OwnerReputation,
    ru2.DisplayName AS EditorDisplayName,
    ru2.Reputation AS EditorReputation,
    cs.CompositeScore,
    ra.LinkTypeName,
    ra.CreationDate AS LinkCreationDate,
    virrn.rn AS TopUserRank,
    rov.CommentText AS LatestOwnerComment,
    rov.CommentDate AS LatestOwnerCommentDate
FROM Composite cs
LEFT JOIN PostHistory ph ON ph.PostId = cs.PostId
LEFT JOIN PostHistory ph2 ON ph2.PostId = cs.PostId
LEFT JOIN Tags t ON t.ExcerptPostId = cs.PostId
LEFT JOIN RelatedPosts ra ON ra.PostId = cs.PostId
LEFT JOIN PostLinks vir ON vir.PostId = cs.PostId
LEFT JOIN TopUsers ru ON ru.Id = cs.OwnerUserId
LEFT JOIN TopUsers ru2 ON ru2.Id = cs.LastEditorUserId
LEFT JOIN LatestOwnerComment rov ON rov.PostId = cs.PostId
ORDER BY cs.CompositeScore DESC
LIMIT 200;