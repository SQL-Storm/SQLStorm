-- {"query": "7929.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2249} 
WITH RECURSIVE UserHierarchy AS (
    SELECT Id, AccountId, 0 as Level
    FROM Users
    WHERE AccountId IS NOT NULL
    UNION ALL
    SELECT u.Id, u.AccountId, uh.Level + 1
    FROM Users u
    INNER JOIN UserHierarchy uh ON u.AccountId = uh.AccountId
    WHERE uh.Level < 3
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDescription,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) * 10 + COALESCE(p.CommentCount, 0) * 5 AS WeightedActivityScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        SUM(COALESCE(ps.Score, 0)) AS TotalScore,
        AVG(COALESCE(ps.Score, 0)) AS AverageScore,
        MAX(ps.LastActivityDate) AS LastActivity,
        STRING_AGG(DISTINCT ps.Title, ', ') AS PostTitles
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
QuestionAnalysis AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.WeightedActivityScore,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.OwnerUserId,
        ps.PostTypeDescription,
        ps.Tags,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 'Answered'
            WHEN ps.LastActivityDate >= DATEADD(DAY, -30, GETDATE()) THEN 'Active'
            ELSE 'Inactive'
        END AS QuestionStatus,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY ps.WeightedActivityScore DESC) AS ActivityQuartile,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.Score DESC) AS UserPostRank
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.WeightedActivityScore,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.OwnerUserId,
        ps.PostTypeDescription,
        ps.Tags,
        ps.ParentId,
        CASE 
            WHEN ps.Score > 0 THEN 'Positive'
            WHEN ps.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS AnswerSentiment,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY ps.ParentId ORDER BY ps.Score DESC) AS ParentAnswerRank
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
)
SELECT 
    'Overall Performance Analysis' AS AnalysisType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT ua.UserId) AS ActiveUsers,
    COUNT(DISTINCT qa.Id) AS TotalQuestions,
    COUNT(DISTINCT aa.Id) AS TotalAnswers,
    AVG(CAST(ua.TotalScore AS FLOAT)) AS AverageUserScore,
    MAX(qa.WeightedActivityScore) AS MaxQuestionActivity,
    MIN(aa.WeightedActivityScore) AS MinAnswerActivity,
    STRING_AGG(
        CASE 
            WHEN qa.QuestionStatus = 'Answered' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            WHEN qa.QuestionStatus = 'Active' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            ELSE CONCAT('Q', qa.Id, '(', qa.Title, ')')
        END, 
        '; '
    ) AS SampleQuestions,
    STRING_AGG(
        CASE 
            WHEN aa.AnswerSentiment = 'Positive' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            WHEN aa.AnswerSentiment = 'Negative' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            ELSE CONCAT('A', aa.Id, '(', aa.Title, ')')
        END, 
        '; '
    ) AS SampleAnswers
FROM UserActivityStats ua
FULL OUTER JOIN QuestionAnalysis qa ON 1=1
FULL OUTER JOIN AnswerAnalysis aa ON 1=1
WHERE 
    (ua.UserId IS NOT NULL OR qa.Id IS NOT NULL OR aa.Id IS NOT NULL)
    AND (ua.LastActivity >= DATEADD(DAY, -30, GETDATE()) OR qa.CreationDate >= DATEADD(DAY, -30, GETDATE()) OR aa.CreationDate >= DATEADD(DAY, -30, GETDATE()))
    AND (
        (qa.Id IS NOT NULL AND qa.Tags IS NOT NULL AND qa.Tags NOT LIKE '%undefined%')
        OR
        (aa.Id IS NOT NULL AND aa.Tags IS NOT NULL AND aa.Tags NOT LIKE '%undefined%')
    )
    AND (
        (ua.UserId IN (SELECT Id FROM UserHierarchy WHERE Level > 0))
        OR
        (qa.Id IS NOT NULL AND qa.Score > 10)
        OR
        (aa.Id IS NOT NULL AND aa.Score > 5)
    )
UNION ALL
SELECT 
    'Detailed User Engagement Analysis' AS AnalysisType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT ua.UserId) AS ActiveUsers,
    COUNT(DISTINCT qa.Id) AS TotalQuestions,
    COUNT(DISTINCT aa.Id) AS TotalAnswers,
    AVG(CAST(ua.TotalScore AS FLOAT)) AS AverageUserScore,
    MAX(qa.WeightedActivityScore) AS MaxQuestionActivity,
    MIN(aa.WeightedActivityScore) AS MinAnswerActivity,
    STRING_AGG(
        CASE 
            WHEN qa.QuestionStatus = 'Answered' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            WHEN qa.QuestionStatus = 'Active' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            ELSE CONCAT('Q', qa.Id, '(', qa.Title, ')')
        END, 
        '; '
    ) AS SampleQuestions,
    STRING_AGG(
        CASE 
            WHEN aa.AnswerSentiment = 'Positive' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            WHEN aa.AnswerSentiment = 'Negative' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            ELSE CONCAT('A', aa.Id, '(', aa.Title, ')')
        END, 
        '; '
    ) AS SampleAnswers
FROM UserActivityStats ua
INNER JOIN QuestionAnalysis qa ON ua.UserId = qa.OwnerUserId
INNER JOIN AnswerAnalysis aa ON qa.Id = aa.ParentId
WHERE 
    ua.LastActivity >= DATEADD(DAY, -60, GETDATE())
    AND (
        qa.AnswerCount > 0 
        OR
        (qa.Tags IS NOT NULL AND qa.Tags <> '' AND qa.Tags LIKE '%sql%')
    )
    AND (
        aa.Score > 0 
        OR
        (aa.Tags IS NOT NULL AND aa.Tags <> '' AND aa.Tags LIKE '%performance%')
    )
    AND EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = ua.UserId 
        AND p.CreationDate >= DATEADD(DAY, -30, GETDATE())
    )
    AND (
        (qa.Score - (SELECT AVG(Score) FROM QuestionAnalysis)) > 5
        OR
        (aa.Score - (SELECT AVG(Score) FROM AnswerAnalysis)) > 2
    )
UNION ALL
SELECT 
    'Tag-Based Performance Analysis' AS AnalysisType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT ua.UserId) AS ActiveUsers,
    COUNT(DISTINCT qa.Id) AS TotalQuestions,
    COUNT(DISTINCT aa.Id) AS TotalAnswers,
    AVG(CAST(ua.TotalScore AS FLOAT)) AS AverageUserScore,
    MAX(qa.WeightedActivityScore) AS MaxQuestionActivity,
    MIN(aa.WeightedActivityScore) AS MinAnswerActivity,
    STRING_AGG(
        CASE 
            WHEN qa.QuestionStatus = 'Answered' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            WHEN qa.QuestionStatus = 'Active' THEN CONCAT('Q', qa.Id, '(', qa.Title, ')')
            ELSE CONCAT('Q', qa.Id, '(', qa.Title, ')')
        END, 
        '; '
    ) AS SampleQuestions,
    STRING_AGG(
        CASE 
            WHEN aa.AnswerSentiment = 'Positive' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            WHEN aa.AnswerSentiment = 'Negative' THEN CONCAT('A', aa.Id, '(', aa.Title, ')')
            ELSE CONCAT('A', aa.Id, '(', aa.Title, ')')
        END, 
        '; '
    ) AS SampleAnswers
FROM UserActivityStats ua
INNER JOIN QuestionAnalysis qa ON ua.UserId = qa.OwnerUserId
INNER JOIN AnswerAnalysis aa ON qa.Id = aa.ParentId
WHERE 
    (qa.Tags LIKE '%sql%' OR qa.Tags LIKE '%performance%' OR aa.Tags LIKE '%sql%' OR aa.Tags LIKE '%performance%')
    AND ua.Reputation > 1000
    AND (
        (qa.Score > 50 AND qa.ViewCount > 1000)
        OR
        (aa.Score > 30 AND aa.ViewCount > 500)
    )
    AND qa.WeightedActivityScore > (
        SELECT AVG(WeightedActivityScore) 
        FROM QuestionAnalysis
    )
    AND (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId = qa.Id AND pl.LinkTypeId = 3
    ) = 0
ORDER BY AnalysisType;