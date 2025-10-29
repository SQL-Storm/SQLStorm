-- {"query": "7298.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2705} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedQuestions,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) as OverallRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.Score DESC ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAverage,
        (p.Score - LAG(p.Score, 1) OVER (ORDER BY p.Score DESC)) / NULLIF(LAG(p.Score, 1) OVER (ORDER BY p.Score DESC), 0) * 100 as ScoreChangePercent,
        COUNT(*) OVER () as TotalPosts,
        (COUNT(*) OVER (ORDER BY p.Score DESC) * 100.0 / COUNT(*) OVER ()) as PercentileRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 0
),
ComplexBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        b.TagBased,
        COUNT(*) OVER (PARTITION BY b.UserId) as TotalBadgesByUser,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) as BadgeSequence,
        DENSE_RANK() OVER (ORDER BY b.Date) as AllBadgesTimeRank,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            ELSE 'Bronze'
        END as BadgeTier,
        CASE 
            WHEN b.TagBased = 1 THEN 'Tag-Based'
            ELSE 'Named Badge'
        END as BadgeType,
        DATEDIFF(day, LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date), b.Date) as DaysSinceLastBadge
    FROM Badges b
),
UserPerformance AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.LastPostDate,
        us.AvgPostScore,
        us.AcceptedQuestions,
        us.AllTags,
        us.BadgeNames,
        CASE 
            WHEN us.Reputation > 10000 THEN 'Expert'
            WHEN us.Reputation > 5000 THEN 'Advanced'
            WHEN us.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        CASE 
            WHEN us.PostCount > 1000 THEN 'Veteran'
            WHEN us.PostCount > 500 THEN 'Experienced'
            WHEN us.PostCount > 100 THEN 'Active'
            ELSE 'Casual'
        END as ActivityLevel,
        CASE 
            WHEN us.BadgeCount >= 20 THEN 'Award-Winning'
            WHEN us.BadgeCount >= 10 THEN 'Achieved'
            ELSE 'Learning'
        END as BadgeLevel,
        CASE 
            WHEN us.AcceptedQuestions > 10 THEN 'Accepted Expert'
            WHEN us.AcceptedQuestions > 5 THEN 'Accepted User'
            ELSE 'Regular User'
        END as AcceptanceLevel,
        (us.QuestionCount * 100.0 / NULLIF(us.PostCount, 0)) as QuestionPercentage,
        (us.AnswerCount * 100.0 / NULLIF(us.PostCount, 0)) as AnswerPercentage,
        (us.UpVotes * 100.0 / NULLIF(us.UpVotes + us.DownVotes, 0)) as UpvotePercentage
    FROM UserStats us
),
TopTaggedQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        STRING_TO_ARRAY(p.Tags, '>') as TagArray,
        ARRAY_LENGTH(STRING_TO_ARRAY(p.Tags, '>'), 1) as TagCount,
        ARRAY_AGG(DISTINCT t.TagName) as TagNames,
        STRING_AGG(DISTINCT t.TagName, ', ') as TagList,
        COUNT(DISTINCT p.Id) OVER () as TotalQuestionCount,
        PERCENT_RANK() OVER (ORDER BY p.Score DESC) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY p.ViewCount DESC) as ViewCumulativePercent,
        VARIANCE(p.Score) OVER (ORDER BY p.CreationDate) as ScoreVariance,
        STDDEV(p.Score) OVER (ORDER BY p.CreationDate) as ScoreStandardDeviation
    FROM Posts p
    JOIN Tags t ON t.TagName = ANY(STRING_TO_ARRAY(p.Tags, '>'))
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.Tags
)

SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.PostCount,
    up.CommentCount,
    up.BadgeCount,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    up.LastPostDate,
    up.AvgPostScore,
    up.AcceptedQuestions,
    up.ReputationLevel,
    up.ActivityLevel,
    up.BadgeLevel,
    up.AcceptanceLevel,
    up.QuestionPercentage,
    up.AnswerPercentage,
    up.UpvotePercentage,
    tp.Score as TopPostScore,
    tp.Title as TopPostTitle,
    tp.ViewCount as TopPostViewCount,
    tp.PostType as TopPostType,
    tp.ScoreRank,
    tp.OverallRank,
    tp.ViewRank,
    tp.ScoreQuartile,
    tp.ScoreChangePercent,
    tp.PercentileRank,
    cb.BadgeTier,
    cb.BadgeType,
    cb.TotalBadgesByUser,
    cb.BadgeSequence,
    cb.DaysSinceLastBadge,
    ttq.Title as MostTaggedTitle,
    ttq.TagList,
    ttq.TagCount,
    ttq.ScorePercentile,
    ttq.ViewCumulativePercent,
    CASE 
        WHEN up.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN up.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationStatus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.Score > 1000) THEN 'High Scoring'
        ELSE 'Regular Scoring'
    END as ScoringStatus,
    CASE 
        WHEN up.BadgeCount > (SELECT AVG(BadgeCount) FROM UserStats) THEN 'Above Average Badges'
        WHEN up.BadgeCount < (SELECT AVG(BadgeCount) FROM UserStats) THEN 'Below Average Badges'
        ELSE 'Average Badges'
    END as BadgeStatus,
    CASE 
        WHEN up.QuestionCount > 0 AND up.AnswerCount > 0 THEN 'Active Contributor'
        WHEN up.QuestionCount > 0 THEN 'Questioner'
        WHEN up.AnswerCount > 0 THEN 'Answerer'
        ELSE 'Inactive'
    END as ContributionType,
    COALESCE(STRING_AGG(DISTINCT up.AllTags, '; '), 'No Tags') as UserTagSummary,
    COALESCE(STRING_AGG(DISTINCT up.BadgeNames, ', '), 'No Badges') as UserBadgeSummary,
    CASE 
        WHEN (up.QuestionCount * 100.0 / NULLIF(up.PostCount, 0)) > 50 THEN 'Question Focused'
        WHEN (up.AnswerCount * 100.0 / NULLIF(up.PostCount, 0)) > 50 THEN 'Answer Focused'
        ELSE 'Balanced'
    END as FocusCategory,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.CreationDate > '2020-01-01') as RecentPostCount,
    (SELECT COALESCE(SUM(p.Score), 0) FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.CreationDate > '2020-01-01') as RecentScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = up.UserId AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) as RecentAcceptedCount,
    CASE 
        WHEN up.PostCount > 0 THEN CAST((up.TotalScore * 100.0 / up.PostCount) AS DECIMAL(10,2))
        ELSE 0
    END as ScorePerPost,
    CASE 
        WHEN up.ViewCount > 0 THEN CAST((up.TotalScore * 100.0 / up.ViewCount) AS DECIMAL(10,2))
        ELSE 0
    END as ScorePerView
FROM UserPerformance up
LEFT JOIN TopPosts tp ON up.UserId = tp.OwnerUserId AND tp.ScoreRank = 1
LEFT JOIN ComplexBadges cb ON up.UserId = cb.UserId
LEFT JOIN TopTaggedQuestions ttq ON up.UserId = ttq.OwnerUserId
WHERE 
    up.Reputation > 1000 
    AND (up.PostCount > 10 OR up.CommentCount > 10 OR up.BadgeCount > 5)
    AND up.LastPostDate >= '2019-01-01'
    AND (tp.Score IS NOT NULL OR cb.UserId IS NOT NULL OR ttq.Id IS NOT NULL)
GROUP BY 
    up.UserId, up.DisplayName, up.Reputation, up.PostCount, up.CommentCount, up.BadgeCount,
    up.QuestionCount, up.AnswerCount, up.TotalScore, up.LastPostDate, up.AvgPostScore,
    up.AcceptedQuestions, up.ReputationLevel, up.ActivityLevel, up.BadgeLevel,
    up.AcceptanceLevel, up.QuestionPercentage, up.AnswerPercentage, up.UpvotePercentage,
    tp.Score, tp.Title, tp.ViewCount, tp.PostType, tp.ScoreRank, tp.OverallRank,
    tp.ViewRank, tp.ScoreQuartile, tp.ScoreChangePercent, tp.PercentileRank,
    cb.BadgeTier, cb.BadgeType, cb.TotalBadgesByUser, cb.BadgeSequence,
    cb.DaysSinceLastBadge, ttq.Title, ttq.TagList, ttq.TagCount, ttq.ScorePercentile,
    ttq.ViewCumulativePercent, up.AllTags, up.BadgeNames, up.ViewCount
HAVING
    COUNT(*) > 0
ORDER BY 
    up.TotalScore DESC,
    up.PostCount DESC,
    up.Reputation DESC,
    up.BadgeCount DESC
LIMIT 1000;