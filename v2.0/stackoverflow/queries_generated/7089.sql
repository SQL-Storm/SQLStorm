-- {"query": "7089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2543} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Senior'
            WHEN u.Reputation > 100 THEN 'Junior'
            ELSE 'Beginner'
        END as RepLevel,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.Score > 100 THEN 'Hot'
            WHEN p.Score > 10 THEN 'Popular'
            WHEN p.Score > 0 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeDays,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as Engagement,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as Favorites,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountDetailed,
        (SELECT STRING_AGG(c.Text, ' | ') FROM Comments c WHERE c.PostId = p.Id LIMIT 3) as SampleComments
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
UserPostActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT pa.PostId) as ActivePosts,
        SUM(pa.Score) as TotalScore,
        AVG(pa.Score) as AvgScore,
        MAX(pa.CreationDate) as LastActivity,
        STRING_AGG(DISTINCT pa.PostType, ', ') as PostTypes,
        MAX(pa.AgeDays) as MaxPostAge
    FROM Users u
    LEFT JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as RelatedPostCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgRelatedScore,
        (SELECT STRING_AGG(p.Title, ', ') FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%' LIMIT 5) as SampleTitles
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
ComplexAnalytics AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.ActivePosts,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastActivity,
        ua.PostTypes,
        ua.MaxPostAge,
        uas.RepLevel,
        uas.RepRank,
        uas.AccountAgeDays,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        ROW_NUMBER() OVER (PARTITION BY uas.RepLevel ORDER BY ua.TotalScore DESC) as LevelScoreRank,
        DENSE_RANK() OVER (ORDER BY ua.TotalScore DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY ua.TotalScore) as ScorePercentile,
        NTILE(10) OVER (ORDER BY ua.ActivePosts) as ActivityDecile,
        CASE 
            WHEN ua.ActivePosts > 50 AND ua.TotalScore > 1000 THEN 'Highly Active'
            WHEN ua.ActivePosts > 10 AND ua.TotalScore > 500 THEN 'Moderately Active'
            WHEN ua.ActivePosts > 0 THEN 'Active'
            ELSE 'Inactive'
        END as ActivityStatus,
        CONCAT(ua.DisplayName, ' (', uas.RepLevel, ')') as FullNameWithRank
    FROM UserPostActivity ua
    JOIN UserActivityStats uas ON ua.UserId = uas.UserId
    WHERE ua.UserId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.ActivePosts,
    ca.TotalScore,
    ca.AvgScore,
    ca.LastActivity,
    ca.PostTypes,
    ca.MaxPostAge,
    ca.RepLevel,
    ca.RepRank,
    ca.AccountAgeDays,
    ca.Questions,
    ca.Answers,
    ca.Comments,
    ca.Badges,
    ca.LevelScoreRank,
    ca.ScoreRank,
    ca.ScorePercentile,
    ca.ActivityDecile,
    ca.ActivityStatus,
    ca.FullNameWithRank,
    (SELECT STRING_AGG(ta.TagName, ', ') FROM Tags ta WHERE ta.TagName IN (SELECT UNNEST(STRING_TO_ARRAY(uas.AllTags, ', ')) WHERE UNNEST(STRING_TO_ARRAY(uas.AllTags, ', ')) IS NOT NULL) LIMIT 5) as SampleTags,
    CASE 
        WHEN ca.RepRank <= 10 THEN 'Top 10'
        WHEN ca.RepRank <= 100 THEN 'Top 100'
        WHEN ca.RepRank <= 1000 THEN 'Top 1K'
        ELSE 'Regular'
    END as ReputationTier,
    CONCAT(
        'Score: ', ca.TotalScore, 
        ', Posts: ', ca.ActivePosts, 
        ', Avg: ', ROUND(ca.AvgScore, 2),
        ', RepStatus: ', ca.RepLevel,
        ', Activity: ', ca.ActivityStatus
    ) as UserSummary,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.CreationDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentPosts30Days,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.CreationDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 7 DAY)) as RecentPosts7Days,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = ca.UserId) as MaxPostScore,
    (SELECT STRING_AGG(DISTINCT p.PostType, ', ') FROM PostAnalysis p WHERE p.OwnerUserId = ca.UserId) as PostTypeDistribution,
    NULL as NullColumnForTesting,
    CASE 
        WHEN ca.TotalScore > (SELECT AVG(TotalScore) FROM ComplexAnalytics) THEN 'Above Average'
        ELSE 'Below Average'
    END as ScoreComparison,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ca.UserId AND v.VoteTypeId = 2) as TotalUpvotesReceived,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ca.UserId AND v.VoteTypeId = 3) as TotalDownvotesReceived
FROM ComplexAnalytics ca
JOIN UserActivityStats uas ON ca.UserId = uas.UserId
WHERE ca.UserId IS NOT NULL
HAVING ca.ActivePosts > 0
ORDER BY ca.TotalScore DESC, ca.RepRank ASC
LIMIT 1000
EXCEPT
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.ActivePosts,
    ca.TotalScore,
    ca.AvgScore,
    ca.LastActivity,
    ca.PostTypes,
    ca.MaxPostAge,
    ca.RepLevel,
    ca.RepRank,
    ca.AccountAgeDays,
    ca.Questions,
    ca.Answers,
    ca.Comments,
    ca.Badges,
    ca.LevelScoreRank,
    ca.ScoreRank,
    ca.ScorePercentile,
    ca.ActivityDecile,
    ca.ActivityStatus,
    ca.FullNameWithRank,
    (SELECT STRING_AGG(ta.TagName, ', ') FROM Tags ta WHERE ta.TagName IN (SELECT UNNEST(STRING_TO_ARRAY(uas.AllTags, ', ')) WHERE UNNEST(STRING_TO_ARRAY(uas.AllTags, ', ')) IS NOT NULL) LIMIT 5) as SampleTags,
    CASE 
        WHEN ca.RepRank <= 10 THEN 'Top 10'
        WHEN ca.RepRank <= 100 THEN 'Top 100'
        WHEN ca.RepRank <= 1000 THEN 'Top 1K'
        ELSE 'Regular'
    END as ReputationTier,
    CONCAT(
        'Score: ', ca.TotalScore, 
        ', Posts: ', ca.ActivePosts, 
        ', Avg: ', ROUND(ca.AvgScore, 2),
        ', RepStatus: ', ca.RepLevel,
        ', Activity: ', ca.ActivityStatus
    ) as UserSummary,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.CreationDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentPosts30Days,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.CreationDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 7 DAY)) as RecentPosts7Days,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = ca.UserId) as MaxPostScore,
    (SELECT STRING_AGG(DISTINCT p.PostType, ', ') FROM PostAnalysis p WHERE p.OwnerUserId = ca.UserId) as PostTypeDistribution,
    NULL as NullColumnForTesting,
    CASE 
        WHEN ca.TotalScore > (SELECT AVG(TotalScore) FROM ComplexAnalytics) THEN 'Above Average'
        ELSE 'Below Average'
    END as ScoreComparison,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ca.UserId AND v.VoteTypeId = 2) as TotalUpvotesReceived,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ca.UserId AND v.VoteTypeId = 3) as TotalDownvotesReceived
FROM ComplexAnalytics ca
JOIN UserActivityStats uas ON ca.UserId = uas.UserId
WHERE ca.UserId IS NOT NULL
AND ca.RepLevel IN ('Elite', 'Senior')
ORDER BY ca.RepRank ASC;