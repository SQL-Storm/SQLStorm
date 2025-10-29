-- {"query": "7499.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2293} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COALESCE(SUM(p.Score) OVER (PARTITION BY u.Id), 0) as TotalPostScore,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT c.Id) as Comments,
        MAX(p.CreationDate) as LatestPostDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Contributor'
            ELSE 'Newbie'
        END as ReputationTier,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Occasional'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.Score, 0) as WikiScore,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as AuthorName,
        pt.Name as PostTypeName,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE 
            WHEN p.Score >= 10 THEN 'Highly Upvoted'
            WHEN p.Score >= 5 THEN 'Upvoted'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Notable'
            ELSE 'Obscure'
        END as ViewCategory,
        COUNT(DISTINCT v.Id) as VoteCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        DATEDIFF(day, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Question'
        END as PostStatus,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 0), 0) as PositiveAnswers,
        ROUND((p.AnswerCount * 100.0) / NULLIF(p.ViewCount, 0), 2) as AnswerToViewRatio,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > DATEADD(year, -2, GETDATE())
      AND p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
),
UserPostPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Badges,
        AVG(cpa.Score) as AvgPostScore,
        AVG(cpa.ViewCount) as AvgViewCount,
        MAX(cpa.Score) as MaxPostScore,
        MAX(cpa.ViewCount) as MaxViewCount,
        COUNT(CASE WHEN cpa.PostStatus = 'Closed' THEN 1 END) as ClosedPosts,
        COUNT(CASE WHEN cpa.PostStatus = 'Answer' THEN 1 END) as AnswerCount,
        COUNT(CASE WHEN cpa.PostStatus <> 'Answer' THEN 1 END) as QuestionCount,
        STDEV(cpa.Score) as ScoreStandardDeviation,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cpa.Score) as MedianScore,
        STRING_AGG(DISTINCT cpa.Title, ', ') WITHIN GROUP (ORDER BY cpa.Score DESC) as TopPostTitles
    FROM UserActivityStats uas
    JOIN ComplexPostAnalysis cpa ON uas.UserId = cpa.OwnerUserId
    WHERE uas.TotalPosts > 0
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalPosts, uas.Questions, uas.Answers, uas.Badges
),
CrossFilterResults AS (
    SELECT 
        upp.UserId,
        upp.DisplayName,
        upp.Reputation,
        upp.TotalPosts,
        upp.AvgPostScore,
        upp.MaxPostScore,
        upp.ScoreStandardDeviation,
        upp.MedianScore,
        upp.TopPostTitles,
        CASE 
            WHEN upp.Reputation > 15000 AND upp.TotalPosts > 10 AND upp.AvgPostScore > 5 THEN 'Power User'
            WHEN upp.Reputation > 5000 AND upp.TotalPosts > 5 THEN 'Active Contributor'
            WHEN upp.Reputation > 1000 AND upp.TotalPosts > 2 THEN 'Regular User'
            ELSE 'Beginner'
        END as UserCategory,
        CASE 
            WHEN upp.AvgPostScore > 15 THEN 'High Performer'
            WHEN upp.AvgPostScore > 5 THEN 'Moderate Performer'
            WHEN upp.AvgPostScore > 0 THEN 'Low Performer'
            ELSE 'Inactive'
        END as PerformanceLevel,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.CreationDate > DATEADD(week, -4, GETDATE())), 0) as RecentPosts,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = upp.UserId AND c.CreationDate > DATEADD(week, -4, GETDATE())), 0) as RecentComments,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = upp.UserId AND b.Date > DATEADD(week, -4, GETDATE())), 0) as RecentBadges
    FROM UserPostPerformance upp
)
SELECT 
    cfr.UserId,
    cfr.DisplayName,
    cfr.Reputation,
    cfr.TotalPosts,
    cfr.AvgPostScore,
    cfr.MaxPostScore,
    cfr.ScoreStandardDeviation,
    cfr.MedianScore,
    cfr.UserCategory,
    cfr.PerformanceLevel,
    cfr.RecentPosts,
    cfr.RecentComments,
    cfr.RecentBadges,
    COALESCE(tp.PopularityLevel, 'Unknown') as TagPopularityLevel,
    COALESCE(tp.TagCount, 0) as TagPopularityCount,
    COALESCE(tp.AvgTagCount, 0) as AverageTagCount,
    COALESCE(ta.TagName, 'No Tag') as PopularTag,
    CASE 
        WHEN cfr.MedianScore > (SELECT AVG(MedianScore) FROM CrossFilterResults) THEN 'Above Average'
        WHEN cfr.MedianScore > (SELECT AVG(MedianScore) FROM CrossFilterResults) * 0.9 THEN 'Near Average'
        ELSE 'Below Average'
    END as PerformanceRank,
    COALESCE(
        (SELECT TOP 1 TagName FROM Tags t 
         JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%' 
         WHERE p.OwnerUserId = cfr.UserId
         GROUP BY t.TagName 
         ORDER BY COUNT(*) DESC), 
        'No Tags'
    ) as MostUsedTag,
    DENSE_RANK() OVER (ORDER BY cfr.Reputation DESC) as ReputationRank,
    ROW_NUMBER() OVER (ORDER BY cfr.AvgPostScore DESC) as ScoreRank,
    CASE 
        WHEN cfr.RecentPosts > 5 THEN 'Very Active'
        WHEN cfr.RecentPosts > 2 THEN 'Active'
        WHEN cfr.RecentPosts > 0 THEN 'Moderately Active'
        ELSE 'Inactive'
    END as RecentActivityLevel,
    IIF(cfr.RecentBadges > 0 AND cfr.RecentComments > 0, 'Engaged', 'Passive') as EngagementType
FROM CrossFilterResults cfr
LEFT JOIN TagPopularity tp ON tp.RankByPopularity <= 10
LEFT JOIN Tags ta ON ta.TagName = (
    SELECT TOP 1 t.TagName 
    FROM Tags t 
    JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%' 
    WHERE p.OwnerUserId = cfr.UserId 
    GROUP BY t.TagName 
    ORDER BY COUNT(*) DESC
)
WHERE cfr.Reputation > 500
  AND cfr.TotalPosts > 0
  AND (cfr.PerformanceLevel IN ('High Performer', 'Moderate Performer') OR cfr.RecentPosts >= 2)
ORDER BY cfr.Reputation DESC, cfr.AvgPostScore DESC, cfr.TotalPosts DESC
OFFSET 100 ROWS
FETCH NEXT 50 ROWS ONLY;