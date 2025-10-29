-- {"query": "7741.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2643} 
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Novice'
            ELSE 'Beginner'
        END as UserTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
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
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.Tags, '') as CleanTags,
        LENGTH(p.Body) as BodyLength,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        NTH_VALUE(p.Score, 1) OVER (ORDER BY p.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxScore,
        NTILE(4) OVER (ORDER BY p.Score) as Quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        SUBSTRING(t.TagName, 1, 1) as FirstLetter,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Lesser'
            ELSE 'Rare'
        END as TagPopularity,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 0
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        DATEDIFF('day', u.CreationDate, u.LastAccessDate) as DaysSinceLastAccess,
        CASE 
            WHEN DATEDIFF('day', u.CreationDate, u.LastAccessDate) > 365 THEN 'Inactive'
            WHEN DATEDIFF('day', u.CreationDate, u.LastAccessDate) > 30 THEN 'Semi-Active'
            ELSE 'Active'
        END as ActivityStatus,
        CASE 
            WHEN u.Reputation > 5000 AND u.UpVotes > 1000 THEN 'PowerUser'
            WHEN u.Reputation > 1000 AND u.UpVotes > 500 THEN 'RegularUser'
            ELSE 'CasualUser'
        END as UserCategory
    FROM Users u
),
CombinedData AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.UserTier,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount as PostCommentCount,
        pa.CreationDate,
        pa.PostType,
        ta.TagName,
        ta.TagCount,
        ta.TagPopularity,
        ua.ActivityStatus,
        ua.UserCategory
    FROM UserStats us
    LEFT JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    LEFT JOIN Tags ta ON pa.Tags IS NOT NULL 
        AND POSITION(ta.TagName IN pa.Tags) > 0 
        AND pa.Tags != ''
    LEFT JOIN UserActivity ua ON us.UserId = ua.UserId
    WHERE us.Reputation > 10000
),
FinalAnalysis AS (
    SELECT 
        cd.UserId,
        cd.DisplayName,
        cd.Reputation,
        cd.UserTier,
        cd.PostCount,
        cd.CommentCount,
        cd.BadgeCount,
        cd.PostId,
        cd.Title,
        cd.Score,
        cd.ViewCount,
        cd.AnswerCount,
        cd.PostCommentCount,
        cd.CreationDate,
        cd.PostType,
        cd.TagName,
        cd.TagCount,
        cd.TagPopularity,
        cd.ActivityStatus,
        cd.UserCategory,
        (cd.Score * cd.TagCount) as WeightedScore,
        (cd.ViewCount * cd.AnswerCount) as EngagementMetric,
        CASE 
            WHEN cd.Reputation > 50000 AND cd.PostCount > 50 THEN 'EliteContributor'
            WHEN cd.Reputation > 25000 AND cd.PostCount > 25 THEN 'SeniorContributor'
            WHEN cd.Reputation > 10000 AND cd.PostCount > 10 THEN 'RegularContributor'
            ELSE 'NewContributor'
        END as ContributorTier,
        ROW_NUMBER() OVER (PARTITION BY cd.UserId ORDER BY cd.Score DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY cd.Reputation DESC) as OverallReputationRank,
        PERCENT_RANK() OVER (ORDER BY cd.Score) as ScorePercentile,
        NTILE(10) OVER (ORDER BY cd.Reputation) as ReputationQuintile,
        CASE 
            WHEN cd.TagCount > 200 THEN 1
            WHEN cd.TagCount > 100 THEN 2
            WHEN cd.TagCount > 50 THEN 3
            ELSE 4
        END as TagFrequencyBucket,
        IIF(cd.PostId IS NOT NULL, 1, 0) as HasPosts,
        IIF(cd.TagName IS NOT NULL, 1, 0) as HasTags,
        COALESCE(cd.TagName, 'No Tags') as SafeTagName,
        REPLACE(cd.Title, ' ', '_') as TitleUnderscore,
        SUBSTRING(cd.Title, 1, 20) as TitleShort,
        CASE 
            WHEN cd.Score > 0 AND cd.ViewCount > 0 THEN ROUND((cd.Score * 100.0 / cd.ViewCount), 2)
            ELSE 0
        END as ScoreToViewRatio
    FROM CombinedData cd
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.UserTier,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.PostId,
    fa.TitleShort,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.PostCommentCount,
    fa.CreationDate,
    fa.PostType,
    fa.TagName,
    fa.TagCount,
    fa.TagPopularity,
    fa.ActivityStatus,
    fa.UserCategory,
    fa.WeightedScore,
    fa.EngagementMetric,
    fa.ContributorTier,
    fa.UserPostRank,
    fa.OverallReputationRank,
    fa.ScorePercentile,
    fa.ReputationQuintile,
    fa.TagFrequencyBucket,
    fa.HasPosts,
    fa.HasTags,
    fa.SafeTagName,
    fa.TitleUnderscore,
    fa.ScoreToViewRatio,
    -- Complex calculations and predicates
    CASE 
        WHEN fa.Reputation > 100000 AND fa.Score > 1000 AND fa.TagCount > 50 THEN 'HighImpactUser'
        WHEN fa.Reputation > 50000 AND fa.Score > 500 AND fa.PostCount > 10 THEN 'MidImpactUser'
        WHEN fa.Reputation > 10000 AND fa.Score > 100 AND fa.CommentCount > 5 THEN 'LowImpactUser'
        ELSE 'AverageUser'
    END as ImpactLevel,
    -- Set operators
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.CreationDate >= '2020-01-01') as RecentPostCount,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.CreationDate >= '2020-01-01') as RecentAvgScore,
    -- Correlated subquery
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = fa.UserId AND ph.PostHistoryTypeId IN (10, 11, 12)) as ModerationActions,
    -- Null logic
    CASE 
        WHEN fa.Score IS NULL THEN 'No Score Data'
        WHEN fa.Score < 0 THEN 'Negative Score'
        WHEN fa.Score = 0 THEN 'Zero Score'
        WHEN fa.Score > 0 AND fa.Score <= 5 THEN 'Low Score'
        WHEN fa.Score > 5 AND fa.Score <= 50 THEN 'Medium Score'
        WHEN fa.Score > 50 THEN 'High Score'
        ELSE 'Unknown'
    END as ScoreClassification,
    -- String expressions
    CONCAT('User:', fa.UserId, '|Reputation:', fa.Reputation, '|Tier:', fa.UserTier) as UserMetadata,
    (SELECT STRING_AGG(ta2.TagName, ', ') FROM Tags ta2 WHERE POSITION(ta2.TagName IN (SELECT COALESCE(pa2.Tags, '') FROM PostAnalysis pa2 WHERE pa2.OwnerUserId = fa.UserId LIMIT 1)) > 0) as UserTagList,
    -- Complex predicates combining multiple conditions
    CASE 
        WHEN fa.Reputation >= 100000 AND fa.PostCount >= 100 AND fa.BadgeCount >= 10 THEN 'LegendaryUser'
        WHEN fa.Reputation >= 50000 AND fa.PostCount >= 50 AND fa.BadgeCount >= 5 THEN 'MasterUser'
        WHEN fa.Reputation >= 10000 AND fa.PostCount >= 10 AND fa.BadgeCount >= 2 THEN 'ContributorUser'
        ELSE 'RegularUser'
    END as CommunityRank,
    -- Window function calculations
    AVG(fa.Score) OVER (PARTITION BY fa.UserTier) as TierAvgScore,
    MAX(fa.Score) OVER (PARTITION BY fa.UserCategory) as CategoryMaxScore,
    LAG(fa.Score, 1) OVER (ORDER BY fa.Reputation) as PreviousUserScore,
    -- Null handling in calculations
    COALESCE(fa.ViewCount, 0) + COALESCE(fa.AnswerCount, 0) + COALESCE(fa.PostCommentCount, 0) as TotalActivityCount
FROM FinalAnalysis fa
WHERE 
    fa.Reputation > 5000 AND 
    (fa.PostType IN ('Question', 'Answer') OR fa.PostType IS NULL) AND
    (fa.TagName IS NOT NULL OR fa.TagName = 'No Tags') AND
    (fa.Score >= 0 OR fa.Score IS NULL) AND
    fa.CreationDate >= '2010-01-01' AND
    (fa.ActivityStatus = 'Active' OR fa.ActivityStatus = 'Semi-Active')
HAVING 
    COUNT(*) OVER (PARTITION BY fa.UserId) > 0
ORDER BY 
    fa.Reputation DESC,
    fa.Score DESC,
    fa.CreationDate DESC
OFFSET 100 ROWS 
FETCH NEXT 50 ROWS ONLY