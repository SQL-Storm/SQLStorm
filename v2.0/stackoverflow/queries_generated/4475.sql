-- {"query": "4475.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1170} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
PostLaggedScore AS (
    SELECT
        p.Id,
        p.Score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousDayScore
    FROM Posts AS p
    WHERE p.Score > 50
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.AnswerCount) FILTER (WHERE p.AnswerCount IS NOT NULL) AS AverageAnswers
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 100
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE
            WHEN SUM(c.Score) > 500 THEN 'High Activity'
            WHEN SUM(c.Score) > 100 THEN 'Medium Activity'
            ELSE 'Low Activity'
        END AS CommentActivityLevel
    FROM Comments AS c
    GROUP BY c.PostId
    HAVING COUNT(c.Id) > 5
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    COALESCE(pls.Score, 0) AS CurrentScore,
    COALESCE(pls.PreviousDayScore, 0) AS ScoreChange,
    upa.TotalPosts AS OwnerTotalPosts,
    upa.TotalScore AS OwnerTotalScore,
    ca.CommentCount,
    ca.TotalCommentScore,
    ca.CommentActivityLevel,
    CASE
        WHEN INSTR(rp.Title, '?') > 0 THEN 'Question'
        WHEN LENGTH(rp.Title) > 50 THEN 'Long Title'
        ELSE 'Standard Title'
    END AS TitleCategory,
    COALESCE(p.OwnerDisplayName, 'Community') AS ActualOwner,
    UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) || '-' || LOWER(rp.PostTypeName) AS CompositeKey
FROM RankedPosts AS rp
LEFT JOIN PostLaggedScore AS pls ON rp.PostId = pls.Id
LEFT JOIN UserPostActivity AS upa ON rp.OwnerDisplayName = upa.UserName
LEFT JOIN CommentAnalysis AS ca ON rp.PostId = ca.PostId
LEFT JOIN Users AS p ON rp.OwnerDisplayName = p.DisplayName
WHERE rp.rn <= 100
  AND (pls.Score > pls.PreviousDayScore OR pls.Score IS NULL)
  AND ca.CommentActivityLevel <> 'Low Activity'
  AND rp.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
UNION ALL
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    COALESCE(pls.Score, 0) AS CurrentScore,
    COALESCE(pls.PreviousDayScore, 0) AS ScoreChange,
    upa.TotalPosts AS OwnerTotalPosts,
    upa.TotalScore AS OwnerTotalScore,
    ca.CommentCount,
    ca.TotalCommentScore,
    ca.CommentActivityLevel,
    CASE
        WHEN INSTR(rp.Title, '?') > 0 THEN 'Question'
        WHEN LENGTH(rp.Title) > 50 THEN 'Long Title'
        ELSE 'Standard Title'
    END AS TitleCategory,
    COALESCE(p.OwnerDisplayName, 'Community') AS ActualOwner,
    UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) || '-' || LOWER(rp.PostTypeName) AS CompositeKey
FROM RankedPosts AS rp
LEFT JOIN PostLaggedScore AS pls ON rp.PostId = pls.Id
LEFT JOIN UserPostActivity AS upa ON rp.OwnerDisplayName = upa.UserName
LEFT JOIN CommentAnalysis AS ca ON rp.PostId = ca.PostId
LEFT JOIN Users AS p ON rp.OwnerDisplayName = p.DisplayName
WHERE rp.rn > 100 AND rp.PostCreationDate < '2022-01-01';
