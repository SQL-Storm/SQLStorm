-- {"query": "7635.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1459} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    COUNT(DISTINCT v.Id) as TotalVotes,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(CURRENT_TIMESTAMP, MIN(p.CreationDate)) as DaysActive,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) END, ',') as AllTags,
    COUNT(DISTINCT c.Id) as CommentCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalViewCount,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END), 0) as AvgQuestionViews,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END), 0) as ClosedQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END), 0) as QuestionsWithAnswers,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END), 0) as FavoriteQuestions,
    
    -- Complex Window Function Analysis
    RANK() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as ActivityRank,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate) as UserRowNum,
    
    -- Correlated Subquery for Reputation Growth Analysis
    (SELECT AVG(r.Reputation) 
     FROM Users r 
     WHERE r.CreationDate <= u.CreationDate 
     AND r.CreationDate >= DATE_SUB(u.CreationDate, INTERVAL 30 DAY)) as AvgReputationLast30Days,
    
    -- CTE for Post Activity Analysis
    ISNULL((SELECT TOP 1 ph.PostHistoryTypeId 
            FROM PostHistory ph 
            WHERE ph.UserId = u.Id 
            ORDER BY ph.CreationDate DESC), 0) as LastPostActivityType,
    
    -- Set Operator Analysis
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) 
        AND EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2)
        THEN 'QuestionAnswerer'
        WHEN EXISTS (SELECT 1 FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1)
        THEN 'Questioner'
        WHEN EXISTS (SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2)
        THEN 'Answerer'
        ELSE 'Inactive'
    END as UserCategory,
    
    -- NULL Logic and Complex Expressions
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != ''
        THEN CONCAT('Website: ', SUBSTRING(u.WebsiteUrl, 1, 20))
        WHEN u.Location IS NOT NULL AND u.Location != ''
        THEN CONCAT('Location: ', u.Location)
        ELSE 'No Profile Info'
    END as ProfileSummary,
    
    -- Mathematical Calculations
    ROUND(SUM(p.Score) * 1.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) as AvgScorePerPost,
    ROUND(COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) as QuestionPercentage,
    ROUND(COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) as AnswerPercentage
    
FROM Users u 
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id

-- Complex Predicates and Calculations
WHERE 
    u.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR)
    AND u.Reputation > 0
    AND (p.Id IS NULL OR p.PostTypeId IN (1, 2))
    AND (u.Id != 0 OR u.Id IS NOT NULL)
    
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate, 
    u.WebsiteUrl, 
    u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    AND (SUM(p.Score) > 0 OR COUNT(DISTINCT v.Id) > 0 OR COUNT(DISTINCT b.Id) > 0)

ORDER BY 
    TotalScore DESC,
    Reputation DESC,
    LatestPostDate DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;