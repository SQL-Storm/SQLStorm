-- {"query": "7753.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1412} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT b.Id) AS Badges,
    COUNT(DISTINCT c.Id) AS Comments,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(AVG(p.Score), 0) AS AvgScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    MAX(p.CreationDate) AS LastPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) AS ActiveDays,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) AS HighViewQuestions,
    
    -- Correlated subquery for finding users with highest reputation in their location
    (SELECT TOP 1 u2.Reputation 
     FROM Users u2 
     WHERE u2.Location = u.Location 
     ORDER BY u2.Reputation DESC) AS MaxReputationInLocation,

    -- Window function for ranking posts by score within each user
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS ScoreRank,
    
    -- Complex conditional logic
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Expert'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Advanced'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    
    -- Set operator for union with a calculated result
    (SELECT COUNT(*) FROM (
        SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
        UNION
        SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2
    ) AS union_result) AS TotalQuestionAnswerCount,
    
    -- String expression with complex operations
    LEFT(UPPER(LEFT(u.DisplayName, 1)) + LOWER(SUBSTRING(u.DisplayName, 2, LEN(u.DisplayName))), 10) AS DisplayNameShort,
    
    -- CTE for ranking badges by type
    (WITH BadgeRankings AS (
        SELECT b.Name, b.Class, COUNT(*) as BadgeCount,
               ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY COUNT(*) DESC) as BadgeRank
        FROM Badges b 
        WHERE b.UserId = u.Id
        GROUP BY b.Name, b.Class
    )
    SELECT STRING_AGG(CONCAT(br.Name, '(', br.BadgeCount, ')'), ', ')
    FROM BadgeRankings br 
    WHERE br.BadgeRank <= 3) AS Top3Badges,
    
    -- NULL handling and complex predicate
    COALESCE(
        (SELECT TOP 1 p2.Title 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 
         ORDER BY p2.CreationDate DESC), 
        'No Questions'
    ) AS LatestQuestionTitle,

    -- Conditional aggregation with complex expressions
    SUM(CASE 
        WHEN p.PostTypeId = 1 AND p.CommentCount > 5 THEN 1 
        WHEN p.PostTypeId = 2 AND p.CommentCount > 3 THEN 1
        ELSE 0 
    END) AS HighCommentActivityPosts,

    -- Subquery with EXISTS
    CASE WHEN EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.UserId = u.Id AND v.VoteTypeId = 1 
        AND v.CreationDate >= DATEADD(month, -6, GETDATE())
    ) THEN 1 ELSE 0 END AS RecentAcceptedVotes,

    -- Calculation with multiple conditions
    (COUNT(DISTINCT p.Id) * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts), 0)) AS PostPercentageOfTotal,

    -- Complex expression with multiple functions
    REPLACE(
        REPLACE(
            REPLACE(
                CONCAT(
                    'User_', 
                    CAST(u.Id AS VARCHAR(10)), 
                    '_', 
                    LEFT(u.DisplayName, 5)
                ), 
                ' ', '_'
            ), 
            '-', '_'
        ), 
        '.', '_'
    ) AS UserIdentifier

FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p3 
    CROSS APPLY STRING_SPLIT(
        CASE WHEN p3.Tags IS NOT NULL THEN RIGHT(p3.Tags, LEN(p3.Tags) - 1) ELSE '' END, 
        '><'
    ) AS tags
    JOIN Tags t ON t.TagName = tags.value
) t ON p.Id = t.PostId

WHERE u.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
  AND u.Reputation > 100
  AND (
    EXISTS (SELECT 1 FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1)
    OR EXISTS (SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2)
  )

GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location

HAVING COUNT(DISTINCT p.Id) >= 5
   AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 2
   AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 1

ORDER BY 
    COALESCE(SUM(p.Score), 0) DESC,
    COUNT(DISTINCT p.Id) DESC,
    u.Reputation DESC;