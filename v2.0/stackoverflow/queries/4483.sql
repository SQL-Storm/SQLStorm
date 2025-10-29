-- {"query": "4483.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1236}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
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
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalViews
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
),
PostCommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountForPost,
        AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    GROUP BY c.PostId
),
UserPostContributions AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOfPosts,
        AVG(CAST(p.ViewCount AS DOUBLE PRECISION)) AS AvgViewCountOfPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
),
HighReputationUsers AS (
    SELECT Id, DisplayName
    FROM Users
    WHERE Reputation > 100000
),
TopLinkedQuestions AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) AS LinkCount
    FROM PostLinks AS pl
    JOIN Posts AS p ON pl.PostId = p.Id
    WHERE p.PostTypeId = 1 AND pl.LinkTypeId = 1
    GROUP BY pl.PostId
    ORDER BY LinkCount DESC
    LIMIT 10
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    rp.ScoreRank,
    rp.PreviousScore,
    rp.NextScore,
    rp.RunningTotalViews,
    pca.CommentCountForPost,
    pca.AvgCommentScore,
    pca.LastCommentDate,
    upca.TotalPostsOwned,
    upca.TotalScoreOfPosts,
    upca.AvgViewCountOfPosts,
    upca.QuestionCount,
    upca.AnswerCount AS UserAnswerCount,
    CASE WHEN hr.Id IS NOT NULL THEN 'High Reputation' ELSE 'Standard Reputation' END AS UserReputationLevel,
    tlq.LinkCount AS IncomingLinksToQuestion,
    CASE
        WHEN rp.Score > 500 AND rp.AnswerCount > 10 THEN 'Popular and Highly Answered'
        WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Closed and Negative Score'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned Content'
        WHEN rp.FavoriteCount > 100 THEN 'Frequently Favorited'
        ELSE 'Standard Post'
    END AS PostCategorization,
    UPPER(SUBSTRING(COALESCE(rp.OwnerDisplayName, 'Unknown') FROM 1 FOR 3)) AS OwnerNameInitials,
    rp.Score + COALESCE(pca.AvgCommentScore, 0) * 10 AS WeightedScore,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Old Closed Post'
        WHEN rp.CreationDate > (cast('2024-10-01' as date) - INTERVAL '7 days') THEN 'Recent Post'
        ELSE 'Mature Post'
    END AS PostAgeCategory,
    rp.PostTypeId
FROM RankedPosts AS rp
LEFT JOIN PostCommentAggregates AS pca ON rp.PostId = pca.PostId
LEFT JOIN UserPostContributions AS upca ON rp.OwnerUserId = upca.OwnerUserId
LEFT JOIN HighReputationUsers AS hr ON rp.OwnerUserId = hr.Id
LEFT JOIN TopLinkedQuestions AS tlq ON rp.PostId = tlq.PostId
WHERE rp.ScoreRank <= 100
ORDER BY rp.PostTypeId, rp.Score DESC;