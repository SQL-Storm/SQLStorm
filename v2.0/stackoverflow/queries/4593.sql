-- {"query": "4593.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 963}
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(Score) AS AvgScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
RecentActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastActivityDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount
    FROM PostHistory ph
    WHERE ph.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 DAY')
    GROUP BY ph.PostId
)
SELECT
    rp.Id AS PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    COALESCE(ca.CommentCount, 0) AS TotalComments,
    COALESCE(ca.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(upc.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(upc.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(upc.AnswerCount, 0) AS UserAnswerCount,
    COALESCE(upc.AvgScore, 0.0) AS UserAvgScore,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN ra.LastActivityDate IS NULL OR ra.LastActivityDate < rp.CreationDate THEN 'No Recent Edits'
        WHEN ra.EditCount > 5 THEN 'Highly Edited'
        ELSE 'Moderately Edited'
    END AS PostStatus,
    u.Reputation,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    CASE WHEN rp.FavoriteCount > 100 THEN 'Popular' ELSE 'Standard' END AS Popularity,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.rn
FROM RankedPosts rp
LEFT JOIN CommentAggregates ca ON rp.Id = ca.PostId
LEFT JOIN UserPostCounts upc ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN RecentActivity ra ON rp.Id = ra.PostId
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
WHERE rp.rn <= 100
  AND rp.PostTypeId IN (1, 2)
  AND rp.Score > 0
  AND (rp.AnswerCount IS NULL OR rp.AnswerCount > 0)
  AND rp.OwnerDisplayName NOT LIKE '%[deleted]%'
  AND rp.Score * COS(rp.ViewCount / 1000.0) > 50
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 50;