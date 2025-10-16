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
        EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400.0 as DaysActive,
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
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0 as DaysSinceActivity,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementScore,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Engaging'
            WHEN p.Score > 50 THEN 'Engaging'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as EngagementLevel,
        TRIM(BOTH '<>' FROM p.Tags) as CleanTags,
        /* STRING_TO_ARRAY is not available in all dialects; emulate with NULL for incompatible engines */
        NULL as TagArray,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserQuestionRank
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > TIMESTAMP '2020-01-01'
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
      AND a.CreationDate > TIMESTAMP '2020-01-01'
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
    
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.PostTypeId = 1 
       AND p2.AcceptedAnswerId IS NOT NULL 
       AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p2.Id AND v.VoteTypeId = 1)) as QuestionsWithAcceptedAnswers,
    
    (SELECT AVG(Reputation) FROM Users u1 
     WHERE u1.Id IN (SELECT DISTINCT OwnerUserId FROM Posts p3 WHERE p3.PostTypeId = 1)) as AvgReputationOfQuestionOwners,
    
    ROW_NUMBER() OVER (ORDER BY (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = us.UserId AND p4.PostTypeId = 1)) as QuestionCountRank,
    
    COALESCE(MAX(CASE WHEN qs.QuestionId IS NOT NULL THEN qs.QuestionId END), 0) as MaxQuestionId,
    COALESCE(MIN(CASE WHEN asa.AnswerId IS NOT NULL THEN asa.AnswerId END), 0) as MinAnswerId,
    
    COALESCE(NULLIF(us.Views, 0), 1) / NULLIF(us.Reputation, 0) as ViewToRepRatio,
    
    (SELECT COUNT(*) FROM (
        SELECT TagName FROM Tags WHERE Count > 100
        UNION ALL
        SELECT 'TagPerformance' as TagName
    ) unioned_tags) as TotalTagAnalysis,
    
    LOWER(CONCAT('User:', SUBSTRING(us.DisplayName FROM 1 FOR 10))) as UserIdentifier,
    REPLACE(UPPER(us.DisplayName), ' ', '_') as FormattedDisplayName,
    
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 1) THEN 'GoldBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 2) THEN 'SilverBadgeHolder'
        ELSE 'NoSpecialBadge'
    END as BadgeStatus,
    
    (EXTRACT(YEAR FROM age(us.LastPostDate, us.FirstPostDate)) * 12
      + EXTRACT(MONTH FROM age(us.LastPostDate, us.FirstPostDate))
      + (EXTRACT(DAY FROM age(us.LastPostDate, us.FirstPostDate)) / 30.0)) as MonthsActive,
    
    COUNT(DISTINCT CASE WHEN us.PostCount > 50 THEN us.UserId END) as HighActivityUsers,
    
    (SELECT COUNT(*) FROM Posts p7 WHERE p7.OwnerUserId = us.UserId AND EXISTS (SELECT 1 FROM Votes v2 WHERE v2.PostId = p7.Id AND v2.VoteTypeId = 2)) as UsersWithUpvotedPosts,
    
    (SELECT COUNT(*) FROM (
        SELECT TagName FROM Tags WHERE Count > 100
        UNION ALL
        SELECT 'TagPerformance' as TagName
    ) unioned_tags) as TotalTagAnalysisDuplicate,
    
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary'
        WHEN us.Reputation > 50000 THEN 'Master'
        WHEN us.Reputation > 10000 THEN 'Expert'
        ELSE 'Regular'
    END as UserTier,
    
    PERCENT_RANK() OVER (ORDER BY COALESCE(qs.Score,0)) as ScorePercentile,
    
    ROUND(SQRT(SUM(us.PostCount * us.PostCount) / NULLIF(COUNT(us.UserId),0)), 2) as PostCountStdDev,
    
    COALESCE(
        TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM REPLACE(COALESCE(qs.Tags,''), '<', ''))), 
        'No Tags'
    ) as NormalizedTags
    
FROM UserStats us
FULL OUTER JOIN QuestionStats qs ON us.UserId = qs.OwnerUserId
FULL OUTER JOIN AnswerStats asa ON qs.QuestionId = asa.QuestionId
FULL OUTER JOIN TagPerformance tp ON qs.QuestionId = tp.PostId
WHERE (us.Reputation > 1000 OR qs.QuestionId IS NOT NULL OR asa.AnswerId IS NOT NULL OR tp.PostId IS NOT NULL)
  AND (COALESCE(us.PostCount, 0) > 0 OR COALESCE(us.QuestionCount, 0) > 0 OR COALESCE(asa.TotalAnswersPerQuestion, 0) > 0)
  AND COALESCE(qs.Score, 0) >= 0
  AND COALESCE(asa.Score, 0) >= 0
  AND (tp.TagName IS NOT NULL OR tp.PostId IS NOT NULL)
GROUP BY us.UserId, us.DisplayName, us.Reputation, us.Views, us.UpVotes, us.DownVotes,
         us.PostCount, us.QuestionCount, us.AnswerCount, us.BadgeCount, us.AvgPostScore, us.LastPostDate, us.FirstPostDate, us.DaysActive, us.ReputationRank, us.ActivityRank,
         qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.AnswerCount, qs.CommentCount, qs.CreationDate, qs.OwnerUserId, qs.Tags, qs.AcceptedAnswerId, qs.OwnerName, qs.DaysSinceActivity, qs.EngagementScore, qs.EngagementLevel, qs.CleanTags, qs.TagArray, qs.UserQuestionRank,
         asa.AnswerId, asa.QuestionId, asa.Score, asa.CreationDate, asa.OwnerUserId, asa.Body, asa.BodyLength, asa.QualityTier, asa.AnswerRank, asa.TotalAnswersPerQuestion,
         tp.TagName, tp.TagCount, tp.PostId, tp.Score, tp.ViewCount, tp.CreationDate, tp.OwnerUserId, tp.RecentPostRank, tp.AvgScorePerTag, tp.TotalScorePerTag, tp.TagCategory, tp.PrevScore
HAVING COUNT(*) > 0
ORDER BY us.Reputation DESC, us.PostCount DESC, qs.Score DESC
LIMIT 1000;