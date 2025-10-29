-- {"query": "7964.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2847} 
WITH UserActivityStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) as Ranking,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                AVG(CAST(p.Score AS FLOAT)) 
            ELSE 0 
        END as AvgPostScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                MAX(p.Score) 
            ELSE 0 
        END as MaxPostScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
PostComplexity AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.Tags,
        p.Title,
        LENGTH(p.Body) as BodyLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ParentId IS NULL THEN 'Question'
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 20 THEN 'ModeratelyVoted' 
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as ScoreCategory,
        CASE 
            WHEN (p.ViewCount IS NOT NULL AND p.ViewCount > 1000) OR (p.ViewCount IS NULL AND p.PostTypeId = 1 AND p.AnswerCount > 5) THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDate,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as UserPostCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankWithinUser,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserTopPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.CreationDate,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as PostRank,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as CumulativeScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        CASE 
            WHEN LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) IS NULL THEN NULL
            ELSE (p.Score - LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) / 
                 NULLIF(LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0)
        END as ScoreChangeRatio
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'HighUsage'
            WHEN t.Count > 100 THEN 'MediumUsage'
            WHEN t.Count > 10 THEN 'LowUsage'
            ELSE 'VeryLowUsage'
        END as UsageLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as UsageRank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as UsagePercentile,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        CASE 
            WHEN LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) IS NOT NULL THEN 
                (t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC)) * 100.0 / 
                NULLIF(LAG(t.Count, 1) OVER (ORDER BY t.Count DESC), 0)
            ELSE NULL 
        END as GrowthRate
    FROM Tags t
    WHERE t.Count > 0
),
FinalAnalysis AS (
    SELECT 
        uas.Id as UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Ranking,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.AvgPostScore,
        uas.MaxPostScore,
        uas.TotalViews,
        COALESCE(pct.PostId, 0) as TopPostId,
        pct.Title as TopPostTitle,
        pct.Score as TopPostScore,
        pct.ViewCount as TopPostViews,
        pct.CommentCount as TopPostComments,
        pct.AnswerCount as TopPostAnswers,
        pct.CreationDate as TopPostDate,
        pct.PostTypeDesc,
        pct.ScoreCategory,
        pct.Popularity,
        pct.ScoreChangeRatio,
        COALESCE(ta.TagName, 'No Tag') as TopTag,
        ta.TagCount as TagCount,
        ta.UsageLevel,
        ta.UsageRank,
        (ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC, uas.TotalPosts DESC)) % 10 as GroupIdentifier,
        CASE 
            WHEN uas.Reputation > 10000 THEN 'Elite'
            WHEN uas.Reputation > 5000 THEN 'Veteran'
            WHEN uas.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END as UserStatus,
        CASE 
            WHEN uas.TotalPosts > 100 THEN 'HighProductivity'
            WHEN uas.TotalPosts > 20 THEN 'MediumProductivity'
            WHEN uas.TotalPosts > 0 THEN 'LowProductivity'
            ELSE 'Inactive'
        END as ProductivityLevel,
        (uas.TotalPosts * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts), 0)) as PostPercentage,
        CASE 
            WHEN uas.LastPostDate IS NOT NULL AND DATEDIFF('day', uas.LastPostDate, CURRENT_TIMESTAMP) > 30 THEN 'Inactive'
            WHEN uas.LastPostDate IS NOT NULL AND DATEDIFF('day', uas.LastPostDate, CURRENT_TIMESTAMP) > 7 THEN 'InactiveButActiveRecently'
            ELSE 'Active'
        END as ActivityStatus,
        ABS(uas.Reputation - (SELECT AVG(Reputation) FROM Users WHERE Id > 0)) as ReputationDeviation,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pct.PostId AND v.VoteTypeId = 2), 0) as UpvotesOnTopPost,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pct.PostId AND v.VoteTypeId = 3), 0) as DownvotesOnTopPost,
        CASE 
            WHEN pct.RankWithinUser = 1 THEN 'TopPost'
            WHEN pct.RankWithinUser <= 3 THEN 'HighRankedPosts'
            ELSE 'OtherPosts'
        END as PostRankCategory,
        COALESCE(uas.LastCommentDate, uas.LastPostDate) as LastActivityDate,
        CASE 
            WHEN DATEDIFF('day', uas.CreationDate, CURRENT_TIMESTAMP) > 365 THEN 'LongTermUser'
            WHEN DATEDIFF('day', uas.CreationDate, CURRENT_TIMESTAMP) > 180 THEN 'MediumTermUser'
            ELSE 'NewUser'
        END as UserTenure,
        CASE 
            WHEN uas.Badges > 50 THEN 'BadgeCollector'
            WHEN uas.Badges > 20 THEN 'ModestBadgeUser'
            WHEN uas.Badges > 0 THEN 'NewBadgeUser'
            ELSE 'NoBadges'
        END as BadgeStatus,
        ABS(uas.AvgPostScore - (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = uas.Id)) as ScoreVariance,
        CASE 
            WHEN uas.MaxPostScore < 0 THEN 'NegativeVoter'
            WHEN uas.MaxPostScore > 50 THEN 'Respected'
            WHEN uas.MaxPostScore > 10 THEN 'Standard'
            ELSE 'Beginner'
        END as ReputationLevel
    FROM UserActivityStats uas
    LEFT JOIN UserTopPosts pct ON uas.Id = pct.OwnerUserId AND pct.PostRank = 1
    LEFT JOIN TagAnalysis ta ON (
        (pct.Tags IS NOT NULL AND LENGTH(pct.Tags) > 0) AND 
        (ta.TagName IN (
            SELECT TRIM(SUBSTRING(t.TagName FROM 2 FOR LENGTH(t.TagName)-2)) 
            FROM (
                SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(pct.Tags, 2, LENGTH(pct.Tags)-2), '><')) AS TagName
            ) t WHERE t.TagName != ''
        )) AND ta.TagCount = (
            SELECT MAX(t2.Count) 
            FROM Tags t2 
            WHERE t2.TagName IN (
                SELECT TRIM(SUBSTRING(t3.TagName FROM 2 FOR LENGTH(t3.TagName)-2))
                FROM (
                    SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(pct.Tags, 2, LENGTH(pct.Tags)-2), '><')) AS TagName
                ) t3 WHERE t3.TagName != ''
            )
        )
    )
    WHERE uas.Id > 0
    AND (pct.PostId IS NULL OR pct.Score > -50)
)
SELECT 
    *,
    CASE 
        WHEN Reputation > 100000 THEN 'GrandMaster'
        WHEN Reputation > 50000 THEN 'Master'
        WHEN Reputation > 10000 THEN 'Expert'
        WHEN Reputation > 1000 THEN 'Advanced'
        WHEN Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as RankingTier,
    (TotalPosts + Comments + Badges) * (Reputation / 1000.0) as ActivityScore,
    (TotalViews / NULLIF(TotalPosts, 0)) as AvgViewsPerPost,
    CASE 
        WHEN TotalViews > 10000 THEN 'VeryPopular'
        WHEN TotalViews > 1000 THEN 'Popular'
        WHEN TotalViews > 100 THEN 'Moderate'
        ELSE 'Low'
    END as ViewPopularity,
    (Questions * 1.0 / NULLIF(TotalPosts, 0)) as QuestionRatio,
    (Answers * 1.0 / NULLIF(TotalPosts, 0)) as AnswerRatio,
    (Comments * 1.0 / NULLIF(TotalPosts, 0)) as CommentRatio,
    CASE 
        WHEN AVGPostScore > 50 THEN 'HighPerformer'
        WHEN AVGPostScore > 10 THEN 'MedPerformer'
        WHEN AVGPostScore > 0 THEN 'LowPerformer'
        ELSE 'NoActivity'
    END as PerformanceLevel,
    ABS(AvgPostScore - (SELECT AVG(Score) FROM Posts)) as PopulationDeviation
FROM FinalAnalysis 
ORDER BY Ranking ASC, ActivityScore DESC
LIMIT 1000;