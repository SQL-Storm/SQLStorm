-- {"query": "4446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 908} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.Score DESC, p.ViewCount DESC) AS RankPerType
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > DATE('now', '-1 year')
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS EditTitleCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS EditBodyCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.UserDisplayName IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount
    FROM Comments c
    GROUP BY c.PostId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostsOwned,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    COALESCE(phs.EditTitleCount, 0) AS TotalEditsToTitle,
    COALESCE(phs.EditBodyCount, 0) AS TotalEditsToBody,
    ca.CommentCount,
    ca.AvgCommentScore,
    ca.AnonymousCommentCount,
    ua.PostsOwned,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    CASE
        WHEN rp.PostScore > 100 AND rp.PostViewCount > 10000 THEN 'High Engagement'
        WHEN rp.PostScore < 0 OR rp.PostViewCount < 100 THEN 'Low Engagement'
        ELSE 'Medium Engagement'
    END AS EngagementLevel,
    LENGTH(rp.Title) AS TitleLength,
    CASE
        WHEN rp.OwnerDisplayName LIKE '%[a-z]%' AND rp.OwnerDisplayName NOT LIKE '%[^a-zA-Z0-9 ]%' THEN 'Valid Name'
        WHEN rp.OwnerDisplayName IS NULL THEN 'Anonymous Owner'
        ELSE 'Special Characters in Name'
    END AS OwnerNameValidation,
    UPPER(SUBSTRING(rp.Title, 1, 3)) AS TitlePrefix,
    DENSE_RANK() OVER (ORDER BY rp.PostScore DESC) AS GlobalScoreRank,
    LAG(rp.PostScore, 1, 0) OVER (ORDER BY rp.PostCreationDate) AS PreviousPostScore
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN CommentAggregates ca ON rp.PostId = ca.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.RankPerType <= 100
ORDER BY rp.PostTypeName, rp.RankPerType;
