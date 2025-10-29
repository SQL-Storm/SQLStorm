-- {"query": "7548.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3104} 
WITH UserStats AS (
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
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as RepTier,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
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
        COALESCE(p.Tags, '') as CleanTags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score >= 10 THEN 'Highly Voted'
            WHEN p.Score >= 5 THEN 'Moderately Voted'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Downvoted'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate, CURRENT_TIMESTAMP)) as AgeInDays,
        CASE 
            WHEN p.CommentCount > 0 THEN 
                ROUND(p.Score * 1.0 / (p.CommentCount + 1), 2)
            ELSE p.Score
        END as ScorePerComment
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPostActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        STRING_AGG(p.Title, '; ') within group (order by p.CreationDate) as RecentTitles,
        MAX(p.CreationDate) as LastActivity,
        STRING_AGG(p.Tags, ', ') within group (order by p.Score desc) as PopularTagCombos
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName
),
ComplexBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId) as UserBadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) as BadgeRank,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeTier,
        CASE 
            WHEN b.Name LIKE '%Excellent%' OR b.Name LIKE '%Master%' OR b.Name LIKE '%Legend%' 
            THEN 1
            WHEN b.Name LIKE '%Great%' OR b.Name LIKE '%Top%' OR b.Name LIKE '%Best%' 
            THEN 2
            WHEN b.Name LIKE '%Good%' OR b.Name LIKE '%Regular%' OR b.Name LIKE '%Average%' 
            THEN 3
            ELSE 4
        END as TierPriority
    FROM Badges b
    WHERE b.Date >= DATEADD(year, -3, CURRENT_TIMESTAMP)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count >= 1000 THEN 'Popular'
            WHEN t.Count >= 500 THEN 'Well-Known'
            WHEN t.Count >= 100 THEN 'Known'
            ELSE 'Niche'
        END as TagPopularity,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as PreviousCount,
        (t.Count - LAG(t.Count) OVER (ORDER BY t.Count DESC)) as CountChange
    FROM Tags t
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COALESCE(SUM(v.Score), 0) as TotalVotes,
        COUNT(v.Id) as VoteCount,
        AVG(v.Score) as AvgVoteScore,
        STRING_AGG(vt.Name, ', ') within group (order by vt.Name) as VoteTypesUsed
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Views,
    us.UpVotes,
    us.DownVotes,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.Badges,
    us.RepTier,
    us.TotalQuestionScore,
    us.TotalAnswerScore,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    CONCAT(COALESCE(ups.RecentTitles, ''), '; ', COALESCE(ups.PopularTagCombos, '')) as UserContentProfile,
    CASE 
        WHEN (us.TotalAnswerScore * 1.0 / NULLIF(us.TotalQuestionScore, 0)) > 1.5 
        THEN 'Answer Focused Expert'
        WHEN us.TotalQuestionScore > us.TotalAnswerScore 
        THEN 'Question Creator'
        WHEN us.TotalAnswerScore > us.TotalQuestionScore 
        THEN 'Answer Contributor'
        ELSE 'Balanced Contributor'
    END as ContributionStyle,
    STRING_AGG(DISTINCT pa.ScoreCategory, ', ') within group (order by pa.ScoreCategory) as PostRatingDistribution,
    STRING_AGG(DISTINCT ta.TagPopularity, ', ') within group (order by ta.PopularityRank) as TagPreferenceAnalysis,
    CASE 
        WHEN us.Badges > 20 THEN 'Active Award Recipient'
        WHEN us.Badges > 10 THEN 'Frequent Award Recipient'
        WHEN us.Badges > 5 THEN 'Regular Award Recipient'
        ELSE 'Occasional Award Recipient'
    END as RecognitionLevel,
    COALESCE(ua.TotalVotes, 0) as RecentTotalVotes,
    COALESCE(ua.VoteCount, 0) as RecentVoteCount,
    ROUND(NULLIF(ua.TotalVotes, 0) * 1.0 / NULLIF(ua.VoteCount, 0), 2) as VotingIntensity,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.UserId = us.UserId 
            AND ph.CreationDate >= DATEADD(month, -3, CURRENT_TIMESTAMP)
            AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        ) THEN 'Active Editor'
        ELSE 'Passive Editor'
    END as EditingStyle,
    CAST(
        CASE 
            WHEN us.Reputation > 1000000 THEN 100
            WHEN us.Reputation > 100000 THEN 90
            WHEN us.Reputation > 10000 THEN 80
            WHEN us.Reputation > 1000 THEN 70
            WHEN us.Reputation > 100 THEN 60
            WHEN us.Reputation > 10 THEN 50
            ELSE 10
        END 
        AS FLOAT
    ) / 100.0 AS PerformanceMultiplier,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p 
            JOIN PostHistory ph ON p.Id = ph.PostId
            WHERE p.OwnerUserId = us.UserId
            AND ph.PostHistoryTypeId IN (10, 12, 13, 14, 15)
            AND ph.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
        ) THEN 'Moderation Activities'
        ELSE 'Regular Participation'
    END as ParticipationLevel,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 1 THEN pa.PostId END) as RecentQuestions,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.PostId END) as RecentAnswers,
    PERCENT_RANK() OVER (ORDER BY us.TotalPosts DESC) as PostPopularityRank,
    AVG(pa.ScorePerComment) as AvgScorePerComment,
    STRING_AGG(DISTINCT b.Name, '; ') within group (order by b.BadgeRank) as RecentBadgeAchievements
FROM UserStats us
LEFT JOIN UserPostActivity ups ON us.UserId = ups.UserId
LEFT JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
LEFT JOIN TagAnalysis ta ON pa.CleanTags IS NOT NULL AND pa.CleanTags != ''
LEFT JOIN UserActivityStats ua ON us.UserId = ua.UserId
LEFT JOIN ComplexBadges b ON us.UserId = b.UserId 
WHERE us.RepTier IN ('Elite', 'Veteran', 'Regular')
GROUP BY 
    us.UserId, 
    us.DisplayName, 
    us.Reputation, 
    us.Views, 
    us.UpVotes, 
    us.DownVotes, 
    us.TotalPosts, 
    us.Questions, 
    us.Answers, 
    us.Badges, 
    us.RepTier, 
    us.TotalQuestionScore, 
    us.TotalAnswerScore, 
    us.AvgQuestionScore, 
    us.AvgAnswerScore, 
    ups.RecentTitles, 
    ups.PopularTagCombos, 
    ua.TotalVotes, 
    ua.VoteCount
HAVING 
    (us.TotalPosts > 10 OR us.Badges > 5)
    AND (us.Questions > 0 OR us.Answers > 0)
ORDER BY us.TotalPosts DESC, us.Reputation DESC

UNION ALL

SELECT 
    -1 as UserId,
    'Total Aggregate Stats' as DisplayName,
    SUM(Reputation) as Reputation,
    SUM(Views) as Views,
    SUM(UpVotes) as UpVotes,
    SUM(DownVotes) as DownVotes,
    SUM(TotalPosts) as TotalPosts,
    SUM(Questions) as Questions,
    SUM(Answers) as Answers,
    SUM(Badges) as Badges,
    '' as RepTier,
    SUM(TotalQuestionScore) as TotalQuestionScore,
    SUM(TotalAnswerScore) as TotalAnswerScore,
    NULL as AvgQuestionScore,
    NULL as AvgAnswerScore,
    '' as UserContentProfile,
    'Aggregate Overview' as ContributionStyle,
    STRING_AGG(DISTINCT ScoreCategory, ', ') as PostRatingDistribution,
    STRING_AGG(DISTINCT TagPopularity, ', ') as TagPreferenceAnalysis,
    'System Overview' as RecognitionLevel,
    SUM(RecentTotalVotes) as RecentTotalVotes,
    SUM(RecentVoteCount) as RecentVoteCount,
    NULL as VotingIntensity,
    'System Level' as EditingStyle,
    1.0 as PerformanceMultiplier,
    'System Wide' as ParticipationLevel,
    SUM(RecentQuestions) as RecentQuestions,
    SUM(RecentAnswers) as RecentAnswers,
    NULL as PostPopularityRank,
    AVG(AvgScorePerComment) as AvgScorePerComment,
    STRING_AGG(DISTINCT RecentBadgeAchievements, '; ') as RecentBadgeAchievements
FROM (
    SELECT 
        us.UserId,
        us.Reputation,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.Badges,
        us.TotalQuestionScore,
        us.TotalAnswerScore,
        pa.ScoreCategory,
        ta.TagPopularity,
        ups.RecentTitles,
        ups.PopularTagCombos,
        ua.TotalVotes as RecentTotalVotes,
        ua.VoteCount as RecentVoteCount,
        pa.PostId,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeId,
        pa.ScorePerComment,
        b.Name as RecentBadgeAchievements
    FROM UserStats us
    LEFT JOIN UserPostActivity ups ON us.UserId = ups.UserId
    LEFT JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.CleanTags IS NOT NULL AND pa.CleanTags != ''
    LEFT JOIN UserActivityStats ua ON us.UserId = ua.UserId
    LEFT JOIN ComplexBadges b ON us.UserId = b.UserId 
    WHERE us.RepTier IN ('Elite', 'Veteran', 'Regular')
) agg
WHERE TotalPosts > 10 OR Badges > 5;

-- This query contains: 
-- - Multiple CTEs with complex logic
-- - Outer joins with left joins and inner joins
-- - Correlated subqueries in CASE expressions
-- - Window functions with ROW_NUMBER, DENSE_RANK, PERCENT_RANK, LAG
-- - Set operators (UNION ALL)
-- - Complicated predicates and expressions with multiple CASE statements
-- - String operations including STRING_AGG, CONCAT, and various text transforms
-- - NULL handling with COALESCE and NULLIF
-- - Date calculations with DATEDIFF and DATEADD
-- - Mathematical calculations and aggregates with GROUP BY
-- - Filtering with HAVING clause
-- - Complex ordering with multiple sort criteria