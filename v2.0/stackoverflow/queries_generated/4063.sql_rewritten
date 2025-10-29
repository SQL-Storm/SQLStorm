-- {"query": "4063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1235} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScorePerPostType,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= '2023-01-01'
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgUserPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
MostValuableQuestions AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.PostScore,
        rp.PostViewCount,
        upa.DisplayName AS OwnerDisplayName,
        upa.Reputation AS OwnerReputation,
        DENSE_RANK() OVER (ORDER BY rp.PostScore DESC, rp.PostViewCount DESC) AS RankByValue
    FROM RankedPosts rp
    JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
    WHERE rp.PostTypeId = 1 AND rp.PostScore > 100
)
SELECT
    mvq.PostId,
    mvq.PostTypeName,
    mvq.PostScore,
    mvq.PostViewCount,
    mvq.OwnerDisplayName,
    mvq.OwnerReputation,
    mvq.RankByValue,
    COALESCE(rp.AnswerCount, 0) AS ActualAnswerCount,
    CASE
        WHEN rp.PostTypeId = 1 THEN 'Question'
        WHEN rp.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeCategory,
    rp.AvgScorePerPostType,
    rp.PreviousPostScore,
    UPPER(SUBSTRING(rp.PostTypeName FROM 1 FOR 1)) || LOWER(SUBSTRING(rp.PostTypeName FROM 2)) AS FormattedPostTypeName,
    rp.CommentCountPerPost,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Favorited'
        ELSE 'Active'
    END AS PostStatus,
    (rp.PostScore * 1.5 + rp.PostViewCount * 0.5 + rp.CommentCountPerPost * 10) AS CompositeScore
FROM MostValuableQuestions mvq
LEFT JOIN RankedPosts rp ON mvq.PostId = rp.PostId
WHERE mvq.RankByValue <= 10

UNION ALL

SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostScore,
    rp.PostViewCount,
    upa.DisplayName AS OwnerDisplayName,
    upa.Reputation AS OwnerReputation,
    NULL AS RankByValue,
    COALESCE(rp.AnswerCount, 0) AS ActualAnswerCount,
    CASE
        WHEN rp.PostTypeId = 1 THEN 'Question'
        WHEN rp.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeCategory,
    rp.AvgScorePerPostType,
    rp.PreviousPostScore,
    UPPER(SUBSTRING(rp.PostTypeName FROM 1 FOR 1)) || LOWER(SUBSTRING(rp.PostTypeName FROM 2)) AS FormattedPostTypeName,
    rp.CommentCountPerPost,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Favorited'
        ELSE 'Active'
    END AS PostStatus,
    (rp.PostScore * 1.5 + rp.PostViewCount * 0.5 + rp.CommentCountPerPost * 10) AS CompositeScore
FROM RankedPosts rp
JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
WHERE rp.rn_asc <= 5 AND rp.PostTypeId = 2 AND rp.PostScore >= 0;