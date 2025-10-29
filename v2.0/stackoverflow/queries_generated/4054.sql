-- {"query": "4054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1317} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_by_creation,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as avg_score_by_type,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) as total_views_by_type,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        COALESCE(p.FavoriteCount, 0) AS NonNullFavoriteCount,
        LEAST(COALESCE(p.Score, 0), COALESCE(p.AnswerCount, 0)) AS MinScoreAnswerCount,
        UPPER(SUBSTRING(p.Title FROM 1 FOR 3)) AS FirstThreeCharsTitle
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TitleEdits,
        STRING_AGG(DISTINCT ph.Comment, '; ') AS UserComments
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id < 100000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(ph.Id) > 5
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Title,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.IsClosed,
    rp.NonNullFavoriteCount,
    rp.MinScoreAnswerCount,
    rp.FirstThreeCharsTitle,
    rp.rn_by_creation,
    rp.avg_score_by_type,
    rp.total_views_by_type,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.PostHistoryCount,
    ua.BodyEdits,
    ua.TitleEdits,
    ua.UserComments,
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS HasUpvote,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountSubquery,
    CASE WHEN ua.LastPostHistoryDate IS NULL THEN 'Never' ELSE CAST(ua.LastPostHistoryDate AS DATE) END AS LastActivityFormatted
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.Score > 10 AND rp.AnswerCount > 0
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Title,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.IsClosed,
    rp.NonNullFavoriteCount,
    rp.MinScoreAnswerCount,
    rp.FirstThreeCharsTitle,
    rp.rn_by_creation,
    rp.avg_score_by_type,
    rp.total_views_by_type,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.PostHistoryCount,
    ua.BodyEdits,
    ua.TitleEdits,
    ua.UserComments,
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS HasUpvote,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountSubquery,
    CASE WHEN ua.LastPostHistoryDate IS NULL THEN 'Never' ELSE CAST(ua.LastPostHistoryDate AS DATE) END AS LastActivityFormatted
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.FavoriteCount > 50 AND rp.PostTypeId = 1
ORDER BY Score DESC, ViewCount DESC;
