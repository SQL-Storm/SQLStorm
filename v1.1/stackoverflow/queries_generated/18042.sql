-- {"query": "18042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1104} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type,
        RANK() OVER (ORDER BY p.Score DESC) AS rank_by_score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_score,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_score,
        AVG(CAST(p.Score AS FLOAT)) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS rolling_avg_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = p.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        UserId,
        UserDisplayName,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        CommentCount,
        LastPostDate,
        ROW_NUMBER() OVER (ORDER BY AnswerCount DESC, TotalAnswerScore DESC) AS user_rank_by_answers
    FROM UserPostEngagement
    WHERE AnswerCount > 50 AND TotalAnswerScore > 1000
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostFavoriteCount,
    rp.AnswerCount,
    rp.rn_by_type,
    rp.rank_by_score,
    rp.previous_score,
    rp.next_score,
    rp.rolling_avg_score,
    COALESCE(u.UserDisplayName, 'Community') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    hru.AnswerCount AS HighRepUserAnswerCount,
    hru.TotalAnswerScore AS HighRepUserTotalAnswerScore,
    CASE
        WHEN rp.PostScore > 100 AND rp.AnswerCount > 5 THEN 'High Performing'
        WHEN rp.PostScore < 0 AND rp.AnswerCount > 0 THEN 'Low Performing'
        ELSE 'Average Performing'
    END AS PerformanceCategory,
    LOWER(SUBSTRING(p.Title FROM 1 FOR 10)) AS First10TitleChars,
    LENGTH(p.Body) AS BodyLength,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.PostCreationDate < (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN 'Old'
        ELSE 'Active'
    END AS PostStatus,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS IsDuplicateLink
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN Posts p ON rp.PostId = p.Id
LEFT JOIN HighReputationUsers hru ON rp.OwnerUserId = hru.UserId
WHERE rp.PostTypeId = 1 -- Focus on Questions
  AND rp.PostScore > 50
  AND rp.PostViewCount > 1000
  AND rp.rank_by_score <= 100
ORDER BY rp.PostCreationDate DESC
LIMIT 500;
