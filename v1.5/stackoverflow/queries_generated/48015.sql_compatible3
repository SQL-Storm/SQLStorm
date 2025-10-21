WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC) AS FavoriteRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
Tagging AS (
    SELECT
        p.Id AS PostId,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS Tags
    FROM Posts p
    JOIN Tags t ON POSITION(t.TagName IN REPLACE(REPLACE(p.Tags, '<', ''), '>', '')) > 0
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
RecentActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 4, 5, 6)
    GROUP BY ph.PostId
),
UserEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.OwnerDisplayName,
    rp.CreationDate,
    tg.Tags,
    ra.LastPostHistoryDate,
    ue.CommentCount AS EngagementCommentCount,
    ue.VoteCount AS EngagementVoteCount,
    ue.UpvoteCount,
    ue.DownvoteCount,
    rp.ViewRank,
    rp.ScoreRank,
    rp.FavoriteRank
FROM RankedPosts rp
LEFT JOIN Tagging tg ON rp.PostId = tg.PostId
LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId
LEFT JOIN UserEngagement ue ON rp.PostId = ue.PostId
WHERE rp.ViewRank <= 1000 OR rp.ScoreRank <= 1000 OR rp.FavoriteRank <= 1000
ORDER BY rp.ViewCount DESC, rp.Score DESC, rp.FavoriteCount DESC
LIMIT 5000;