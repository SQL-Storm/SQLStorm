-- {"query": "7641.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2195} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        ROW_NUMBER() OVER (ORDER BY u.CreationDate ASC) as JoinOrder
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p2 ON p.Id = p2.ParentId
    LEFT JOIN Tags t ON p2.Tags IS NOT NULL AND t.TagName IN (
        SELECT unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><'))
    )
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        CASE 
            WHEN Reputation >= 1000000 THEN 'Legendary'
            WHEN Reputation >= 100000 THEN 'Master'
            WHEN Reputation >= 10000 THEN 'Expert'
            WHEN Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(PostCount, 0) + COALESCE(BadgeCount, 0) + COALESCE(CommentCount, 0) as ActivityScore,
        CASE 
            WHEN AnswerCount > 0 AND QuestionCount > 0 THEN 'Both'
            WHEN AnswerCount > 0 THEN 'Answerer'
            WHEN QuestionCount > 0 THEN 'Questioner'
            ELSE 'Inactive'
        END as ContributionType,
        LEAD(DisplayName) OVER (ORDER BY Reputation DESC) as NextHigherUser,
        LAG(DisplayName) OVER (ORDER BY Reputation DESC) as PreviousLowerUser
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.ParentId,
        COALESCE(p.Score, 0) * COALESCE(p.ViewCount, 0) / NULLIF(p.AnswerCount + 1, 0) as EngagementScore,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            WHEN p.Score >= 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreCategory,
        CASE 
            WHEN p.CommentCount > 10 THEN 'Highly Commented'
            WHEN p.CommentCount > 5 THEN 'Moderately Commented'
            WHEN p.CommentCount > 0 THEN 'Sparingly Commented'
            ELSE 'No Comments'
        END as CommentStatus,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankByType,
        RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) as RecencyRank,
        NTILE(4) OVER (ORDER BY p.Score) as QuartileScore,
        COUNT(*) OVER () as TotalPosts,
        AVG(p.Score) OVER () as AvgScore,
        MAX(p.Score) OVER () as MaxScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count >= 10000 THEN 'Popular'
            WHEN t.Count >= 1000 THEN 'Moderate'
            WHEN t.Count >= 100 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.TagName) OVER (ORDER BY t.Count DESC) as PrevPopularTag,
        LEAD(t.TagName) OVER (ORDER BY t.Count DESC) as NextPopularTag,
        SUM(t.Count) OVER (ORDER BY t.Count DESC) as CumulativeTagCount,
        COUNT(*) OVER () as TotalTags,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
    WHERE t.Count > 0
),
ComplexActivity AS (
    SELECT 
        ra.UserId,
        ra.DisplayName,
        ra.Reputation,
        ra.PostCount,
        ra.QuestionCount,
        ra.AnswerCount,
        ra.BadgeCount,
        ra.CommentCount,
        ra.VoteCount,
        ra.ReputationRank,
        ra.ReputationTier,
        ra.ActivityScore,
        ra.ContributionType,
        pa.PostId,
        pa.Title,
        pa.Score as PostScore,
        pa.ViewCount,
        pa.AnswerCount as PostAnswerCount,
        pa.CommentCount as PostCommentCount,
        pa.EngagementScore,
        pa.ScoreCategory,
        pa.CommentStatus,
        pa.ScoreRankByType,
        ta.TagName,
        ta.TagCount,
        ta.PopularityLevel,
        ta.PopularityRank,
        CASE 
            WHEN ra.Reputation > (SELECT AVG(Reputation) FROM Users) 
                 AND ra.PostCount > (SELECT AVG(PostCount) FROM UserStats) 
                 AND ra.ReputationTier IN ('Master', 'Legendary') 
            THEN 1 ELSE 0 
        END as HighActiveUser,
        CASE 
            WHEN pa.EngagementScore > (SELECT AVG(EngagementScore) FROM PostAnalysis) 
                 AND pa.ScoreCategory IN ('High', 'Medium') 
                 AND pa.CommentStatus IN ('Highly Commented', 'Moderately Commented')
            THEN 1 ELSE 0 
        END as EngagedPost
    FROM RankedUsers ra
    INNER JOIN PostAnalysis pa ON ra.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.Tags IS NOT NULL AND ta.TagName IN (
        SELECT unnest(string_to_array(substring(pa.Tags, 2, length(pa.Tags)-2), '><'))
    )
    WHERE ra.UserId IS NOT NULL
),
FinalAnalysis AS (
    SELECT 
        *,
        CASE 
            WHEN HighActiveUser = 1 AND EngagedPost = 1 THEN 'Elite Contributor'
            WHEN HighActiveUser = 1 THEN 'Active Contributor'
            WHEN EngagedPost = 1 THEN 'Engaged Contributor'
            ELSE 'Regular Contributor'
        END as ContributorStatus,
        (Reputation * 0.1 + PostCount * 10 + BadgeCount * 5 + CommentCount * 2 + VoteCount * 0.5) as CompositeScore,
        (ABS(Reputation - (SELECT AVG(Reputation) FROM Users)) / NULLIF((SELECT STDDEV(Reputation) FROM Users), 0)) as ReputationZScore,
        PERCENT_RANK() OVER (ORDER BY CompositeScore DESC) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY Reputation DESC) as ReputationPercentile,
        NTILE(5) OVER (ORDER BY CompositeScore) as PerformanceTier,
        ROW_NUMBER() OVER (ORDER BY CompositeScore DESC) as OverallRank
    FROM ComplexActivity
    WHERE PostScore IS NOT NULL
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.BadgeCount,
    fa.CommentCount,
    fa.VoteCount,
    fa.ReputationTier,
    fa.ContributionType,
    fa.PostId,
    fa.Title,
    fa.PostScore,
    fa.ViewCount,
    fa.PostAnswerCount,
    fa.PostCommentCount,
    fa.EngagementScore,
    fa.ScoreCategory,
    fa.CommentStatus,
    fa.TagName,
    fa.TagCount,
    fa.PopularityLevel,
    fa.ContributorStatus,
    fa.CompositeScore,
    fa.ReputationZScore,
    fa.ScorePercentile,
    fa.PerformanceTier,
    fa.OverallRank,
    CASE 
        WHEN fa.CompositeScore > (SELECT AVG(CompositeScore) FROM FinalAnalysis) 
        THEN 'Above Average'
        WHEN fa.CompositeScore > (SELECT AVG(CompositeScore) FROM FinalAnalysis) * 0.9 
        THEN 'Near Average'
        ELSE 'Below Average'
    END as PerformanceLevel,
    (SELECT COUNT(*) FROM FinalAnalysis) as TotalAnalysedUsers,
    (SELECT MAX(CompositeScore) FROM FinalAnalysis) as MaxCompositeScore,
    (SELECT MIN(CompositeScore) FROM FinalAnalysis) as MinCompositeScore,
    (SELECT AVG(CompositeScore) FROM FinalAnalysis) as AvgCompositeScore,
    (SELECT STRING_AGG(DisplayName, ', ') FROM FinalAnalysis fa2 WHERE fa2.PerformanceTier = 1) as TopTierUsers,
    (SELECT STRING_AGG(DisplayName, ', ') FROM FinalAnalysis fa3 WHERE fa3.ScorePercentile >= 0.9) as Top10PercentUsers,
    (SELECT COUNT(*) FROM FinalAnalysis WHERE HighActiveUser = 1) as HighActiveUsers,
    (SELECT COUNT(*) FROM FinalAnalysis WHERE EngagedPost = 1) as EngagedPosts,
    (SELECT COUNT(*) FROM FinalAnalysis WHERE ContributorStatus = 'Elite Contributor') as EliteContributors
FROM FinalAnalysis fa
WHERE fa.CompositeScore > 0
ORDER BY fa.CompositeScore DESC
LIMIT 1000;