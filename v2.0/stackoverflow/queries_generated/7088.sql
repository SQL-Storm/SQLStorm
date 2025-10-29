-- {"query": "7088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2310} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgesCount,
        STRING_AGG(CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END, ', ') as TagBadges,
        STRING_AGG(CASE WHEN b.TagBased = 0 THEN b.Name ELSE NULL END, ', ') as NamedBadges,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as MaxQuestionViews,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) as MaxAnswerViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPostHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as PreviousDate,
        DATEDIFF('day', LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate), ph.CreationDate) as DaysSinceLastActivity
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Title as WikiTitle,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularityLevel,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
UserActivityPatterns AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        CASE 
            WHEN COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) > 10 THEN 'HighlyActive'
            WHEN COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) > 5 THEN 'Active'
            WHEN COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) > 0 THEN 'Moderate'
            ELSE 'Inactive'
        END as ActivityLevel,
        COUNT(DISTINCT ph.PostId) as DistinctPostsWithActivity,
        COUNT(ph.Id) as TotalActivities,
        MIN(ph.CreationDate) as FirstActivity,
        MAX(ph.CreationDate) as LastActivity
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.TotalQuestionScore,
    ups.TotalAnswerScore,
    ups.AvgQuestionScore,
    ups.AvgAnswerScore,
    ups.LastPostDate,
    ups.BadgesCount,
    ups.TagBadges,
    ups.NamedBadges,
    ups.MaxQuestionViews,
    ups.MaxAnswerViews,
    COALESCE(ta.Count, 0) as TagCount,
    COALESCE(ta.TagPopularityLevel, 'Unknown') as TagPopularity,
    COALESCE(uap.ActivityLevel, 'Unknown') as UserActivityLevel,
    COALESCE(uap.DistinctPostsWithActivity, 0) as ActivePostCount,
    COALESCE(uap.TotalActivities, 0) as TotalUserActivities,
    CASE 
        WHEN ups.Reputation > 10000 AND ups.TotalPosts > 100 AND ups.BadgesCount > 50 THEN 'Elite'
        WHEN ups.Reputation > 5000 AND ups.TotalPosts > 50 AND ups.BadgesCount > 25 THEN 'Veteran'
        WHEN ups.Reputation > 1000 AND ups.TotalPosts > 10 THEN 'Contributor'
        ELSE 'Regular'
    END as UserTier,
    RANK() OVER (ORDER BY ups.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY ups.TotalPosts DESC) as PostActivityRank,
    NTILE(4) OVER (ORDER BY ups.Reputation DESC) as ReputationQuartile,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = ups.UserId AND PostTypeId = 1 ORDER BY CreationDate DESC LIMIT 1)
            AND ph.PostHistoryTypeId = 10 
            AND ph.CreationDate > '2023-01-01'
        ) THEN 1
        ELSE 0
    END as RecentClosedQuestions,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.OwnerUserId = ups.UserId 
            AND p.PostTypeId = 2 
            AND p.Score < 0 
            AND p.CreationDate > '2023-01-01'
        ) THEN 1
        ELSE 0
    END as RecentPoorAnswers,
    COALESCE(
        (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = ups.UserId AND PostTypeId = 1), 
        0
    ) as AverageQuestionScore,
    COALESCE(
        (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = ups.UserId AND PostTypeId = 2), 
        0
    ) as AverageAnswerScore,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p 
         INNER JOIN PostHistory ph ON p.Id = ph.PostId 
         WHERE p.OwnerUserId = ups.UserId 
         AND ph.PostHistoryTypeId IN (10, 12, 13) 
         AND ph.CreationDate > '2023-01-01'), 
        0
    ) as RecentEdits,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ups.UserId AND c.CreationDate > '2023-01-01'), 
        0
    ) as RecentComments,
    CASE 
        WHEN ups.Reputation > 10000 THEN 'High'
        WHEN ups.Reputation > 5000 THEN 'Medium'
        WHEN ups.Reputation > 1000 THEN 'Low'
        ELSE 'VeryLow'
    END as ReputationLevel
FROM UserPostStats ups
LEFT JOIN TagAnalytics ta ON EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = ups.UserId 
    AND p.Tags LIKE '%' || ta.TagName || '%'
)
LEFT JOIN UserActivityPatterns uap ON ups.UserId = uap.UserId
WHERE ups.TotalPosts > 0
AND (ups.Reputation > 5000 OR ups.BadgesCount > 10)
AND ups.LastPostDate > '2022-01-01'
UNION
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.TotalQuestionScore,
    ups.TotalAnswerScore,
    ups.AvgQuestionScore,
    ups.AvgAnswerScore,
    ups.LastPostDate,
    ups.BadgesCount,
    ups.TagBadges,
    ups.NamedBadges,
    ups.MaxQuestionViews,
    ups.MaxAnswerViews,
    COALESCE(ta.Count, 0) as TagCount,
    COALESCE(ta.TagPopularityLevel, 'Unknown') as TagPopularity,
    COALESCE(uap.ActivityLevel, 'Unknown') as UserActivityLevel,
    COALESCE(uap.DistinctPostsWithActivity, 0) as ActivePostCount,
    COALESCE(uap.TotalActivities, 0) as TotalUserActivities,
    CASE 
        WHEN ups.Reputation > 10000 AND ups.TotalPosts > 100 AND ups.BadgesCount > 50 THEN 'Elite'
        WHEN ups.Reputation > 5000 AND ups.TotalPosts > 50 AND ups.BadgesCount > 25 THEN 'Veteran'
        WHEN ups.Reputation > 1000 AND ups.TotalPosts > 10 THEN 'Contributor'
        ELSE 'Regular'
    END as UserTier,
    RANK() OVER (ORDER BY ups.Reputation DESC) as ReputationRank,
    DENSE_RANK() OVER (ORDER BY ups.TotalPosts DESC) as PostActivityRank,
    NTILE(4) OVER (ORDER BY ups.Reputation DESC) as ReputationQuartile,
    0 as RecentClosedQuestions,
    0 as RecentPoorAnswers,
    0 as AverageQuestionScore,
    0 as AverageAnswerScore,
    0 as RecentEdits,
    0 as RecentComments,
    'None' as ReputationLevel
FROM UserPostStats ups
LEFT JOIN TagAnalytics ta ON ta.Count IS NULL
LEFT JOIN UserActivityPatterns uap ON uap.UserId IS NULL
WHERE ups.Reputation < 1000
AND ups.LastPostDate > '2020-01-01'
AND NOT EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = ups.UserId 
    AND p.CreationDate > '2023-01-01'
)
ORDER BY Reputation DESC, TotalPosts DESC, LastPostDate DESC
LIMIT 1000;