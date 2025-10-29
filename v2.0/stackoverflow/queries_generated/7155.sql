-- {"query": "7155.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2410} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) as CommentRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestionAuthors AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as QuestionCount,
        SUM(p.Score) as TotalQuestionScore,
        AVG(p.Score) as AvgQuestionScore,
        STRING_AGG(p.Title, ' | ' ORDER BY p.CreationDate) as QuestionTitles
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2020-01-01'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 5
),
TagEngagement AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        STRING_AGG(p.Title, ' | ' ORDER BY p.CreationDate DESC) as RecentQuestions,
        COUNT(DISTINCT p.OwnerUserId) as UniqueAuthors,
        AVG(p.Score) as AvgScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2021-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(p.Id) > 10
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        LENGTH(p.Body) as BodyLength,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 500 THEN 'Medium'
            ELSE 'Low'
        END as ViewCategory,
        CASE 
            WHEN p.Score > 50 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as RecentByType,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        FIRST_VALUE(p.Score) OVER (ORDER BY p.ViewCount DESC) as HighestViewedScore,
        NTILE(4) OVER (ORDER BY p.CreationDate) as Quarter
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate > '2020-01-01'
),
UserPostBehavior AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as PostCount,
        PERCENT_RANK() OVER (ORDER BY COUNT(p.Id)) as PostPercentile,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.Score) as MinScore,
        STDEV(p.Score) as ScoreStdDev,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) as PositiveScoreCount,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) as NegativeScoreCount,
        CASE 
            WHEN SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) = 0 THEN 'No Upvotes'
            WHEN SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) = 0 THEN 'All Upvotes'
            WHEN SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) > SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) THEN 'Upvote Dominant'
            ELSE 'Downvote Dominant'
        END as ScoreTrend
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalBadges,
    uas.TotalScore,
    uas.LastPostDate,
    uas.PostRank,
    uas.CommentRank,
    uas.BadgeRank,
    COALESCE(tqa.QuestionCount, 0) as QuestionCount,
    COALESCE(tqa.TotalQuestionScore, 0) as TotalQuestionScore,
    COALESCE(tqa.AvgQuestionScore, 0) as AvgQuestionScore,
    COALESCE(te.TagName, 'No Tags') as MostActiveTag,
    COALESCE(te.TagCount, 0) as TagCount,
    COALESCE(pca.Title, 'No Recent Posts') as RecentPostTitle,
    COALESCE(pca.Score, 0) as RecentPostScore,
    COALESCE(pca.ViewCategory, 'Unknown') as ViewCategory,
    COALESCE(pca.Popularity, 'Unknown') as Popularity,
    COALESCE(ups.PostCount, 0) as UserPostCount,
    COALESCE(ups.PostPercentile, 0) as PostPercentile,
    COALESCE(ups.ScoreTrend, 'No Data') as ScoreTrend,
    'Complexity Analysis' as AnalysisType,
    CASE 
        WHEN uas.TotalPosts > 100 AND uas.TotalScore > 5000 THEN 'High Activity'
        WHEN uas.TotalPosts > 50 AND uas.TotalScore > 1000 THEN 'Medium Activity'
        WHEN uas.TotalPosts > 10 THEN 'Low Activity'
        ELSE 'Inactive'
    END as ActivityLevel,
    CASE 
        WHEN uas.Reputation > 100000 THEN 'Elite'
        WHEN uas.Reputation > 10000 THEN 'Veteran'
        WHEN uas.Reputation > 1000 THEN 'Regular'
        ELSE 'Beginner'
    END as UserTier,
    COALESCE(tqa.QuestionTitles, '') as QuestionTitles,
    COALESCE(te.RecentQuestions, '') as RecentQuestions,
    COALESCE(ups.TotalScore, 0) as TotalScoreByUser,
    COALESCE(ups.AvgScore, 0) as AvgScoreByUser,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 1) as QuestionCountByUser,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 2) as AnswerCountByUser
FROM UserActivityStats uas
LEFT JOIN TopQuestionAuthors tqa ON uas.UserId = tqa.UserId
LEFT JOIN TagEngagement te ON (SELECT t.TagName FROM Tags t INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' WHERE p.OwnerUserId = uas.UserId AND p.CreationDate > '2020-01-01' LIMIT 1) = te.TagName
LEFT JOIN PostComplexityAnalysis pca ON pca.Id = (
    SELECT p.Id FROM Posts p 
    WHERE p.OwnerUserId = uas.UserId 
    AND p.CreationDate > '2020-01-01' 
    ORDER BY p.CreationDate DESC 
    LIMIT 1
)
LEFT JOIN UserPostBehavior ups ON uas.UserId = ups.UserId
WHERE uas.UserId IN (
    SELECT UserId 
    FROM (
        SELECT uas.UserId, uas.TotalPosts, uas.TotalScore
        FROM UserActivityStats uas
        WHERE uas.TotalPosts > 20
    ) x
    WHERE x.TotalScore > (
        SELECT AVG(TotalScore) * 1.5 
        FROM UserActivityStats
    )
)
UNION ALL
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalBadges,
    uas.TotalScore,
    uas.LastPostDate,
    uas.PostRank,
    uas.CommentRank,
    uas.BadgeRank,
    COALESCE(tqa.QuestionCount, 0) as QuestionCount,
    COALESCE(tqa.TotalQuestionScore, 0) as TotalQuestionScore,
    COALESCE(tqa.AvgQuestionScore, 0) as AvgQuestionScore,
    'N/A' as MostActiveTag,
    0 as TagCount,
    'No Recent Posts' as RecentPostTitle,
    0 as RecentPostScore,
    'Unknown' as ViewCategory,
    'Unknown' as Popularity,
    COALESCE(ups.PostCount, 0) as UserPostCount,
    COALESCE(ups.PostPercentile, 0) as PostPercentile,
    COALESCE(ups.ScoreTrend, 'No Data') as ScoreTrend,
    'Cross-Platform Analysis' as AnalysisType,
    CASE 
        WHEN uas.TotalPosts > 50 AND uas.TotalScore > 5000 THEN 'High Activity'
        WHEN uas.TotalPosts > 20 AND uas.TotalScore > 1000 THEN 'Medium Activity'
        WHEN uas.TotalPosts > 5 THEN 'Low Activity'
        ELSE 'Inactive'
    END as ActivityLevel,
    CASE 
        WHEN uas.Reputation > 50000 THEN 'Elite'
        WHEN uas.Reputation > 5000 THEN 'Veteran'
        WHEN uas.Reputation > 500 THEN 'Regular'
        ELSE 'Beginner'
    END as UserTier,
    '' as QuestionTitles,
    '' as RecentQuestions,
    COALESCE(ups.TotalScore, 0) as TotalScoreByUser,
    COALESCE(ups.AvgScore, 0) as AvgScoreByUser,
    0 as QuestionCountByUser,
    0 as AnswerCountByUser
FROM UserActivityStats uas
WHERE uas.UserId NOT IN (
    SELECT UserId 
    FROM TopQuestionAuthors tqa
    UNION
    SELECT UserId 
    FROM UserPostBehavior ups
)
AND uas.Reputation BETWEEN 100 AND 1000
ORDER BY uas.TotalPosts DESC, uas.TotalScore DESC, uas.Reputation DESC
LIMIT 1000;