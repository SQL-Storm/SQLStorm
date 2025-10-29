-- {"query": "7276.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2338}
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LatestPostDate,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) as NegativeScorePosts,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT u.Location, ', ') as Locations,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        uas.*,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) as UserRank,
        RANK() OVER (ORDER BY AvgScore DESC) as AvgScoreRank
    FROM UserActivityStats uas
),
TopUsers AS (
    SELECT * FROM RankedUsers WHERE UserRank <= 100
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        COALESCE(p.Tags, '') as TagsClean,
        LENGTH(COALESCE(p.Tags, '')) as TagsLength,
        CASE 
            WHEN p.ViewCount > 1000 OR p.Score > 10 THEN 'High Engagement'
            WHEN p.ViewCount > 500 OR p.Score > 5 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2015-01-01'
    AND p.PostTypeId IN (1, 2)
),
UserTagAnalysis AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        STRING_AGG(DISTINCT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), ', ') as UserTags,
        COUNT(DISTINCT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) as DistinctTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY u.Id, u.DisplayName
),
ComplexMetrics AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeDesc,
        pa.TagsClean,
        pa.TagsLength,
        pa.EngagementLevel,
        CASE 
            WHEN pa.Score > 0 THEN (pa.Score * 1.0 / NULLIF(pa.ViewCount, 0)) * 100
            ELSE 0 
        END as ScoreToViewRatio,
        CASE 
            WHEN pa.ViewCount > 0 THEN (pa.AnswerCount * 1.0 / NULLIF(pa.ViewCount, 0)) * 100
            ELSE 0 
        END as AnswerToViewRatio,
        CASE 
            WHEN pa.ViewCount > 0 THEN (pa.CommentCount * 1.0 / NULLIF(pa.ViewCount, 0)) * 100
            ELSE 0 
        END as CommentToViewRatio,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pa.CreationDate)) / 86400 AS INTEGER) as DaysSinceCreation,
        CASE 
            WHEN pa.Score > 50 THEN 'Very High'
            WHEN pa.Score > 25 THEN 'High'
            WHEN pa.Score > 10 THEN 'Medium'
            WHEN pa.Score > 0 THEN 'Low'
            ELSE 'None'
        END as ScoreCategory,
        CASE 
            WHEN pa.ViewCount > 5000 THEN 'Viral'
            WHEN pa.ViewCount > 1000 THEN 'Popular'
            WHEN pa.ViewCount > 500 THEN 'Moderate'
            ELSE 'Minor'
        END as ViewCategory,
        CASE WHEN pa.TagsLength > 50 THEN 'Many Tags' ELSE 'Few Tags' END as TagDensity
    FROM PostAnalysis pa
),
CombinedMetrics AS (
    SELECT 
        cm.PostId,
        cm.Title,
        cm.Score,
        cm.ViewCount,
        cm.CreationDate,
        cm.OwnerUserId,
        cm.PostTypeDesc,
        cm.TagsClean,
        cm.TagsLength,
        cm.EngagementLevel,
        cm.ScoreToViewRatio,
        cm.AnswerToViewRatio,
        cm.CommentToViewRatio,
        cm.DaysSinceCreation,
        cm.ScoreCategory,
        cm.ViewCategory,
        cm.TagDensity,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationCategory,
        CASE 
            WHEN cm.DaysSinceCreation < 30 THEN 'New'
            WHEN cm.DaysSinceCreation < 365 THEN 'Active'
            ELSE 'Established'
        END as PostAgeGroup,
        CASE 
            WHEN cm.ScoreToViewRatio > 5 THEN 'Highly Engaging'
            WHEN cm.ScoreToViewRatio > 2 THEN 'Engaging'
            WHEN cm.ScoreToViewRatio > 1 THEN 'Moderate Engagement'
            ELSE 'Low Engagement'
        END as EngagementIntensity
    FROM ComplexMetrics cm
    INNER JOIN Users u ON cm.OwnerUserId = u.Id
    WHERE cm.Score > 0
),
FinalAnalysis AS (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.OwnerUserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostTypeDesc,
        ca.EngagementLevel,
        ca.ScoreToViewRatio,
        ca.AnswerToViewRatio,
        ca.CommentToViewRatio,
        ca.DaysSinceCreation,
        ca.ScoreCategory,
        ca.ViewCategory,
        ca.TagDensity,
        ca.ReputationCategory,
        ca.PostAgeGroup,
        ca.EngagementIntensity,
        ROW_NUMBER() OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.Score DESC) as UserPostRank,
        RANK() OVER (ORDER BY ca.ScoreToViewRatio DESC) as RatioRank,
        DENSE_RANK() OVER (ORDER BY ca.ViewCount DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY ca.Score DESC) as ScorePercentile,
        AVG(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as AvgScoreByUser,
        SUM(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as TotalScoreByUser,
        LAG(ca.Score, 1) OVER (ORDER BY ca.Score DESC) as PrevScore,
        LEAD(ca.Score, 1) OVER (ORDER BY ca.Score DESC) as NextScore,
        NTILE(4) OVER (ORDER BY ca.Score DESC) as Quartile,
        CASE 
            WHEN ca.Score > (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1) THEN 'Above Average'
            ELSE 'Below Average'
        END as ScoreComparison,
        NULLIF(
            LENGTH(ca.Title) - LENGTH(REPLACE(ca.Title, ' ', '')), 
            LENGTH(ca.Title)
        ) as WordCount,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = ca.PostId 
             AND v.VoteTypeId IN (2, 3)), 0
        ) as VoteCount,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ca.PostId), 0
        ) as CommentCountActual
    FROM CombinedMetrics ca
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.OwnerUserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostTypeDesc,
    fa.EngagementLevel,
    fa.ScoreToViewRatio,
    fa.AnswerToViewRatio,
    fa.CommentToViewRatio,
    fa.DaysSinceCreation,
    fa.ScoreCategory,
    fa.ViewCategory,
    fa.TagDensity,
    fa.ReputationCategory,
    fa.PostAgeGroup,
    fa.EngagementIntensity,
    fa.UserPostRank,
    fa.RatioRank,
    fa.ViewRank,
    fa.ScorePercentile,
    fa.AvgScoreByUser,
    fa.TotalScoreByUser,
    fa.PrevScore,
    fa.NextScore,
    fa.Quartile,
    fa.ScoreComparison,
    fa.WordCount,
    fa.VoteCount,
    fa.CommentCountActual,
    CASE 
        WHEN fa.Score > 100 AND fa.ViewCount > 5000 THEN 'Elite Post'
        WHEN fa.Score > 50 AND fa.ViewCount > 1000 THEN 'Prominent Post'
        WHEN fa.Score > 25 AND fa.ViewCount > 500 THEN 'Notable Post'
        ELSE 'Regular Post'
    END as PostStatus,
    CASE 
        WHEN fa.ViewCategory IN ('Viral', 'Popular') AND fa.ScoreCategory IN ('Very High', 'High') THEN 'Trending'
        WHEN fa.ViewCategory IN ('Moderate', 'Minor') AND fa.ScoreCategory IN ('Medium', 'Low') THEN 'Stable'
        ELSE 'Uncategorized'
    END as TrendStatus,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.OwnerUserId AND p.PostTypeId = 1) as TotalQuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.OwnerUserId AND p.PostTypeId = 2) as TotalAnswerCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.OwnerUserId AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')) as RecentPostCount
FROM FinalAnalysis fa
WHERE fa.Score >= 10
AND fa.ViewCount >= 100
AND fa.DaysSinceCreation <= 365
AND fa.Reputation >= 100
ORDER BY fa.Score DESC, fa.ViewCount DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;