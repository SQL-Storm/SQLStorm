-- {"query": "4704.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1121} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankByUser,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScoreByUser,
        COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(c.Score) AS TotalCommentScoreOnPost,
        AVG(CAST(LEN(c.Text) AS FLOAT)) AS AvgCommentLength
    FROM Comments AS c
    GROUP BY c.PostId
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(rp.Score AS FLOAT)) AS AvgPostScore,
        MAX(rp.PostCreationDate) AS LastPostDate,
        SUM(rp.ViewCount) AS TotalViewsReceived,
        SUM(rp.FavoriteCount) AS TotalFavoritesReceived,
        COUNT(DISTINCT rp.ClosedDate) AS ClosedPostCount
    FROM Users AS u
    LEFT JOIN RankedPosts AS rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    rp.IsClosed,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    ca.CommentCountOnPost,
    ca.TotalCommentScoreOnPost,
    ca.AvgCommentLength,
    upa.TotalPosts AS UserTotalPosts,
    upa.QuestionCount AS UserQuestionCount,
    upa.AnswerCount AS UserAnswerCount,
    upa.AvgPostScore AS UserAvgPostScore,
    upa.LastPostDate AS UserLastPostDate,
    upa.TotalViewsReceived AS UserTotalViewsReceived,
    upa.TotalFavoritesReceived AS UserTotalFavoritesReceived,
    upa.ClosedPostCount AS UserClosedPostCount,
    rp.PostRankByUser,
    rp.PreviousPostScore,
    rp.CumulativeScoreByUser,
    CAST(rp.TotalPostsByUser AS FLOAT) / COUNT(upa.UserId) OVER () AS UserActivityProportion,
    CASE
        WHEN rp.Score > 100 AND rp.FavoriteCount > 50 AND rp.AnswerCount > 10 AND rp.PostCreationDate < DATEADD(day, -30, GETDATE()) THEN 'Popular & Mature'
        WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Negatively Scored & Closed'
        WHEN rp.OwnerUserId IS NULL THEN 'Community Owned'
        ELSE 'Standard'
    END AS PostCategory,
    COALESCE(rp.ViewCount, 0) + COALESCE(rp.Score, 0) * 10 AS WeightedScore
FROM RankedPosts AS rp
LEFT JOIN CommentAggregates AS ca ON rp.PostId = ca.PostId
LEFT JOIN UserPostActivity AS upa ON rp.OwnerUserId = upa.UserId
WHERE rp.PostTypeId = 1 -- Focus on Questions for this benchmark
AND (rp.OwnerUserId IS NOT NULL OR rp.CommunityOwnedDate IS NOT NULL)
ORDER BY rp.PostCreationDate DESC
LIMIT 100;
