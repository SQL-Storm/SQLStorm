-- {"query": "7524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2749} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        COUNT(DISTINCT v.Id) as VotesCast,
        COUNT(DISTINCT c.Id) as CommentsMade,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTagsUsed,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RankByReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostComplexityAnalysis AS (
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AnswerCount > 0 THEN 
                        CASE WHEN p.Score > 10 THEN 'Highly Engaged Question' 
                             WHEN p.Score > 5 THEN 'Moderately Engaged Question' 
                             ELSE 'Low Engagement Question' 
                        END
                    ELSE 'No Answers Question'
                END
            WHEN p.PostTypeId = 2 THEN 
                CASE WHEN p.Score > 5 THEN 'High Value Answer' ELSE 'Standard Answer' END
            ELSE 'Other Post Type'
        END as PostEngagementLevel,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Underexposed'
        END as ViewLevel,
        CASE 
            WHEN p.CommentCount > 15 THEN 'Highly Commented'
            WHEN p.CommentCount > 5 THEN 'Moderately Commented'
            ELSE 'Low Comment Volume'
        END as CommentLevel,
        LENGTH(p.Body) as BodyLength,
        CAST(SUBSTRING(p.Tags, 1, 1) AS INTEGER) as TagsCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostRanking AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) as ActivityRank,
        PERCENT_RANK() OVER (ORDER BY COUNT(p.Id)) as ActivityPercentile,
        NTILE(4) OVER (ORDER BY AVG(p.Score)) as ScoreQuartile
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.Score IS NOT NULL AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTagsAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Notable'
            ELSE 'Niche'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        AVG(t.Count) OVER () as AvgTagCount,
        (t.Count - AVG(t.Count) OVER ()) / STDDEV(t.Count) OVER () as TagZScore
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.BadgesEarned,
        uas.VotesCast,
        uas.CommentsMade,
        uas.RankByReputation,
        uas.AllTagsUsed,
        upr.TotalPostCount,
        upr.QuestionCount,
        upr.AnswerCount,
        upr.TotalScore,
        upr.AvgScore,
        upr.ScoreRank,
        upr.ActivityRank,
        pca.PostId,
        pca.Title,
        pca.Score as PostScore,
        pca.ViewCount,
        pca.AnswerCount as PostAnswerCount,
        pca.CommentCount,
        pca.FavoriteCount,
        pca.CreationDate as PostCreationDate,
        pca.PostEngagementLevel,
        pca.ViewLevel,
        pca.CommentLevel,
        pca.BodyLength,
        pca.TagsCount,
        tta.TagName,
        tta.TagCount,
        tta.TagPopularity,
        tta.TagRank,
        tta.TagZScore,
        CASE 
            WHEN uas.Reputation < 1000 THEN 'Newbie'
            WHEN uas.Reputation < 5000 THEN 'Intermediate'
            WHEN uas.Reputation < 10000 THEN 'Advanced'
            ELSE 'Expert'
        END as UserTier,
        CASE 
            WHEN uas.TotalPosts > 100 THEN 'Power User'
            WHEN uas.TotalPosts > 50 THEN 'Regular User'
            WHEN uas.TotalPosts > 10 THEN 'Occasional User'
            ELSE 'New User'
        END as ActivityLevel,
        CASE 
            WHEN uas.BadgesEarned > 20 THEN 'Badge Collector'
            WHEN uas.BadgesEarned > 10 THEN 'Moderate Collector'
            ELSE 'Casual Collector'
        END as BadgeLevel,
        DATEDIFF('day', uas.LastPostDate, NOW()) as DaysSinceLastActivity,
        MOD(uas.UserId, 100) as UserGroup,
        CASE 
            WHEN uas.Views > 5000 THEN 'Well Known'
            WHEN uas.Views > 1000 THEN 'Notable'
            ELSE 'Regular'
        END as VisibilityLevel
    FROM UserActivityStats uas
    LEFT JOIN UserPostRanking upr ON uas.UserId = upr.UserId
    LEFT JOIN PostComplexityAnalysis pca ON uas.UserId = pca.OwnerUserId
    LEFT JOIN TopTagsAnalysis tta ON (SUBSTRING(uas.AllTagsUsed, 1, 1) = SUBSTRING(tta.TagName, 1, 1) OR uas.AllTagsUsed LIKE '%' || tta.TagName || '%')
    WHERE uas.UserId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.BadgesEarned,
    ca.VotesCast,
    ca.CommentsMade,
    ca.RankByReputation,
    ca.AllTagsUsed,
    ca.TotalPostCount,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.TotalScore,
    ca.AvgScore,
    ca.ScoreRank,
    ca.ActivityRank,
    ca.PostId,
    ca.Title,
    ca.PostScore,
    ca.ViewCount,
    ca.PostAnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.PostCreationDate,
    ca.PostEngagementLevel,
    ca.ViewLevel,
    ca.CommentLevel,
    ca.BodyLength,
    ca.TagsCount,
    ca.TagName,
    ca.TagCount,
    ca.TagPopularity,
    ca.TagRank,
    ca.TagZScore,
    ca.UserTier,
    ca.ActivityLevel,
    ca.BadgeLevel,
    ca.DaysSinceLastActivity,
    ca.UserGroup,
    ca.VisibilityLevel,
    ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC, ca.TotalScore DESC) as OverallRanking,
    RANK() OVER (PARTITION BY ca.UserTier ORDER BY ca.Reputation DESC) as TierRank,
    DENSE_RANK() OVER (ORDER BY ca.TagCount DESC) as TagPopularityRank,
    CASE 
        WHEN ca.Reputation > (SELECT AVG(Reputation) FROM Users) AND 
             ca.TotalPosts > (SELECT AVG(TotalPosts) FROM UserActivityStats) THEN 'Active Contributor' 
        ELSE 'Regular Contributor'
    END as ContributionStatus,
    CASE 
        WHEN ca.FavoriteCount IS NOT NULL AND ca.FavoriteCount > 5 THEN 'Popular Content Creator'
        WHEN ca.CommentCount > 10 THEN 'Engaged Community Member'
        ELSE 'Passive User'
    END as CommunityRole,
    ABS(ca.Reputation - (SELECT AVG(Reputation) FROM Users)) as ReputationDeviation,
    (ca.Reputation * ca.TotalPosts) / NULLIF(ca.BadgesEarned, 0) as EngagementIndicator,
    CASE 
        WHEN ca.PostScore > 0 AND ca.ViewCount > 0 THEN 
            ROUND((ca.PostScore * 1.0 / NULLIF(ca.ViewCount, 0)), 4)
        ELSE 0 
    END as ScoreToViewRatio,
    CASE 
        WHEN ca.AvgScore IS NOT NULL AND ca.AvgScore > 0 THEN 
            ROUND((ca.AvgScore * 1.0 / NULLIF(ca.TotalPosts, 0)), 2)
        ELSE 0 
    END as AvgScorePerPost,
    CASE 
        WHEN ca.BadgesEarned > 0 THEN 
            ROUND((ca.BadgesEarned * 1.0 / NULLIF(ca.TotalPosts, 0)), 2)
        ELSE 0 
    END as BadgesPerPost,
    COALESCE(ca.AllTagsUsed, 'No Tags') as SafeTags,
    CONCAT('User-', ca.UserId, '-Tier-', ca.UserTier) as UserIdentifier,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ca.UserId AND PostTypeId = 1) as UserQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ca.UserId AND PostTypeId = 2) as UserAnswers,
    (SELECT COUNT(*) FROM Comments WHERE UserId = ca.UserId) as UserComments,
    (SELECT COUNT(*) FROM Badges WHERE UserId = ca.UserId) as UserBadges,
    CASE 
        WHEN ca.UserTier = 'Expert' AND ca.TagCount > 50 THEN 'Subject Matter Expert'
        WHEN ca.UserTier = 'Advanced' AND ca.TagCount > 25 THEN 'Specialized Contributor'
        ELSE 'General Contributor'
    END as ExpertiseLevel,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Votes WHERE UserId = ca.UserId AND VoteTypeId = 2) AND
             EXISTS (SELECT 1 FROM Votes WHERE UserId = ca.UserId AND VoteTypeId = 3) THEN 'Balanced Voter'
        WHEN EXISTS (SELECT 1 FROM Votes WHERE UserId = ca.UserId AND VoteTypeId = 2) THEN 'Upvoter'
        WHEN EXISTS (SELECT 1 FROM Votes WHERE UserId = ca.UserId AND VoteTypeId = 3) THEN 'Downvoter'
        ELSE 'Neutral Voter'
    END as VotingPattern,
    CASE 
        WHEN ca.DaysSinceLastActivity IS NULL THEN 'Unknown Activity'
        WHEN ca.DaysSinceLastActivity > 365 THEN 'Inactive User'
        WHEN ca.DaysSinceLastActivity > 30 THEN 'Sporadic User'
        WHEN ca.DaysSinceLastActivity > 7 THEN 'Regular User'
        ELSE 'Active User'
    END as ActivityStatus
FROM CombinedAnalysis ca
WHERE (ca.Reputation > 0 OR ca.TotalPosts > 0 OR ca.BadgesEarned > 0)
  AND ca.UserId IS NOT NULL
  AND LOWER(ca.DisplayName) NOT LIKE '%bot%'
  AND ca.DisplayName IS NOT NULL
  AND ca.UserTier IS NOT NULL
HAVING 
    COUNT(*) OVER() > 500
    OR ca.Reputation > 5000
    OR ca.TotalScore > 10000
    OR ca.BadgesEarned > 30
ORDER BY ca.Reputation DESC, ca.TotalScore DESC, ca.BadgesEarned DESC
LIMIT 5000;