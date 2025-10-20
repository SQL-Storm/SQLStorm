-- {"query": "29052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2507} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        MIN(p.CreationDate) as FirstPostDate,
        DATEDIFF('DAY', MIN(p.CreationDate), MAX(p.CreationDate)) as DaysActive,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        DATEDIFF('DAY', p.CreationDate, p.LastActivityDate) as DaysSinceActivity,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementScore,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Engaging'
            WHEN p.Score > 50 THEN 'Engaging'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as EngagementLevel,
        TRIM(BOTH '<>' FROM p.Tags) as CleanTags,
        STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><') as TagArray,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserQuestionRank
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
    AND p.CreationDate > '2020-01-01'
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.Body,
        LENGTH(a.Body) as BodyLength,
        CASE 
            WHEN a.Score > 10 THEN 'High Quality'
            WHEN a.Score > 5 THEN 'Good'
            WHEN a.Score > 0 THEN 'Minimal'
            ELSE 'No Votes'
        END as QualityTier,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
        COUNT(*) OVER (PARTITION BY a.ParentId) as TotalAnswersPerQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2 
    AND a.CreationDate > '2020-01-01'
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate DESC) as RecentPostRank,
        AVG(p.Score) OVER (PARTITION BY t.TagName) as AvgScorePerTag,
        SUM(p.Score) OVER (PARTITION BY t.TagName) as TotalScorePerTag,
        CASE 
            WHEN AVG(p.Score) OVER (PARTITION BY t.TagName) > 50 THEN 'Popular Tag'
            WHEN AVG(p.Score) OVER (PARTITION BY t.TagName) > 20 THEN 'Moderate Tag'
            ELSE 'Niche Tag'
        END as TagCategory,
        LAG(p.Score) OVER (PARTITION BY t.TagName ORDER BY p.CreationDate) as PrevScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 
    AND LENGTH(t.TagName) > 2
)
SELECT 
    'Performance Benchmark Results' as ReportTitle,
    COUNT(DISTINCT us.UserId) as TotalActiveUsers,
    COUNT(DISTINCT qs.QuestionId) as TotalQuestions,
    COUNT(DISTINCT asa.AnswerId) as TotalAnswers,
    COUNT(DISTINCT tp.PostId) as TotalTaggedPosts,
    AVG(us.AvgPostScore) as AvgUserPostScore,
    AVG(qs.Score) as AvgQuestionScore,
    AVG(asa.Score) as AvgAnswerScore,
    MAX(qs.DaysSinceActivity) as MaxDaysSinceActivity,
    MIN(qs.CreationDate) as EarliestQuestionDate,
    MAX(qs.CreationDate) as LatestQuestionDate,
    AVG(tp.TotalScorePerTag) as AvgTagScore,
    COUNT(*) as TotalRecordsFromComplexJoins,
    
    -- Complex calculations and subqueries
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.PostTypeId = 1 
     AND p2.AcceptedAnswerId IS NOT NULL 
     AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p2.Id AND v.VoteTypeId = 1)) as QuestionsWithAcceptedAnswers,
    
    (SELECT AVG(Reputation) FROM Users u1 
     WHERE u1.Id IN (SELECT DISTINCT OwnerUserId FROM Posts p3 WHERE p3.PostTypeId = 1)) as AvgReputationOfQuestionOwners,
    
    -- Window function with complex partitioning
    ROW_NUMBER() OVER (ORDER BY (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = us.UserId AND p4.PostTypeId = 1)) as QuestionCountRank,
    
    -- Outer join patterns
    COALESCE(MAX(CASE WHEN qs.QuestionId IS NOT NULL THEN qs.QuestionId END), 0) as MaxQuestionId,
    COALESCE(MIN(CASE WHEN asa.AnswerId IS NOT NULL THEN asa.AnswerId END), 0) as MinAnswerId,
    
    -- NULL handling and COALESCE with complex expressions
    COALESCE(NULLIF(us.Views, 0), 1) / NULLIF(us.Reputation, 0) as ViewToRepRatio,
    
    -- Set operators in a complex way
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.PostTypeId = 1 GROUP BY p5.OwnerUserId HAVING COUNT(*) > 10 
     INTERSECT 
     SELECT COUNT(*) FROM Posts p6 WHERE p6.PostTypeId = 2 GROUP BY p6.OwnerUserId HAVING COUNT(*) > 50) as ComplexSetResult1,
    
    -- String functions and expressions
    LOWER(CONCAT('User:', SUBSTRING(us.DisplayName, 1, 10))) as UserIdentifier,
    REPLACE(UPPER(us.DisplayName), ' ', '_') as FormattedDisplayName,
    
    -- Subquery in WHERE clause
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 1) THEN 'GoldBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 2) THEN 'SilverBadgeHolder'
        ELSE 'NoSpecialBadge'
    END as BadgeStatus,
    
    -- Complex date expressions
    DATEDIFF('MONTH', us.FirstPostDate, us.LastPostDate) as MonthsActive,
    
    -- Aggregation with HAVING clause
    COUNT(DISTINCT CASE WHEN us.PostCount > 50 THEN us.UserId END) as HighActivityUsers,
    
    -- Correlated subquery with EXISTS
    (SELECT COUNT(*) FROM Posts p7 WHERE p7.OwnerUserId = us.UserId AND EXISTS (SELECT 1 FROM Votes v2 WHERE v2.PostId = p7.Id AND v2.VoteTypeId = 2)) as UsersWithUpvotedPosts,
    
    -- CTE usage with UNION ALL
    (SELECT COUNT(*) FROM (
        SELECT TagName FROM Tags WHERE Count > 100
        UNION ALL
        SELECT 'TagPerformance' as TagName
    ) unioned_tags) as TotalTagAnalysis,
    
    -- Conditional logic and CASE expressions
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary'
        WHEN us.Reputation > 50000 THEN 'Master'
        WHEN us.Reputation > 10000 THEN 'Expert'
        ELSE 'Regular'
    END as UserTier,
    
    -- Nested window functions with complex expressions
    PERCENT_RANK() OVER (ORDER BY AVG(qs.Score)) as ScorePercentile,
    
    -- Complex mathematical calculations
    ROUND(SQRT(SUM(us.PostCount * us.PostCount) / COUNT(us.UserId)), 2) as PostCountStdDev,
    
    -- Handling of special cases in string processing
    COALESCE(
        TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM REPLACE(qs.Tags, '<', ''))), 
        'No Tags'
    ) as NormalizedTags
    
FROM UserStats us
FULL OUTER JOIN QuestionStats qs ON us.UserId = qs.OwnerUserId
FULL OUTER JOIN AnswerStats asa ON qs.QuestionId = asa.QuestionId
FULL OUTER JOIN TagPerformance tp ON qs.QuestionId = tp.PostId

-- Complex predicates
WHERE (us.Reputation > 1000 OR qs.QuestionId IS NOT NULL OR asa.AnswerId IS NOT NULL OR tp.PostId IS NOT NULL)
AND (COALESCE(us.PostCount, 0) > 0 OR COALESCE(qs.QuestionCount, 0) > 0 OR COALESCE(asa.AnswerCount, 0) > 0)
AND (CASE WHEN qs.Score IS NOT NULL THEN qs.Score ELSE 0 END) >= 0
AND (CASE WHEN asa.Score IS NOT NULL THEN asa.Score ELSE 0 END) >= 0
AND (tp.TagName IS NOT NULL OR tp.PostId IS NOT NULL)

GROUP BY us.UserId, us.DisplayName, us.Reputation, us.Views, us.PostCount, us.QuestionCount, us.AnswerCount, 
         us.BadgeCount, us.AvgPostScore, us.LastPostDate, us.FirstPostDate, us.DaysActive, us.ReputationRank, 
         us.ActivityRank, qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.AnswerCount, qs.CommentCount, 
         qs.CreationDate, qs.OwnerUserId, qs.Tags, qs.AcceptedAnswerId, qs.OwnerName, qs.DaysSinceActivity, 
         qs.EngagementScore, qs.EngagementLevel, qs.CleanTags, qs.TagArray, qs.UserQuestionRank, 
         asa.AnswerId, asa.QuestionId, asa.Score, asa.CreationDate, asa.OwnerUserId, asa.Body, asa.BodyLength, 
         asa.QualityTier, asa.AnswerRank, asa.TotalAnswersPerQuestion, tp.TagName, tp.TagCount, tp.PostId, 
         tp.Score, tp.ViewCount, tp.CreationDate, tp.OwnerUserId, tp.RecentPostRank, tp.AvgScorePerTag, 
         tp.TotalScorePerTag, tp.TagCategory, tp.PrevScore

HAVING COUNT(*) > 0
ORDER BY us.Reputation DESC, us.PostCount DESC, qs.Score DESC
LIMIT 1000;