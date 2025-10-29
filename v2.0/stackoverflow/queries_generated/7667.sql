-- {"query": "7667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2650} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Contributor'
            ELSE 'Member'
        END as UserTier,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        MAX(p.CreationDate) as LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as RankByScore,
        RANK() OVER (PARTITION BY CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags, 1, 10) ELSE 'no_tag' END ORDER BY p.Score DESC) as RankByTag
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TopAnswers AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId,
        p.Score,
        p.CreationDate,
        u.DisplayName as OwnerName,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY p.ParentId, p.Score DESC) as RankByQuestion
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
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
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as RelatedPosts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScorePerTag
    FROM Tags t
),
PostActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.LastEditDate,
        CASE 
            WHEN p.LastActivityDate > p.CreationDate + INTERVAL '7 days' THEN 'Active'
            WHEN p.LastActivityDate > p.CreationDate + INTERVAL '1 day' THEN 'Recently Active'
            ELSE 'Inactive'
        END as ActivityStatus,
        DATEDIFF(day, p.CreationDate, COALESCE(p.LastActivityDate, p.CreationDate)) as DaysActive,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankByType,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTH_VALUE(p.Title, 1) OVER (ORDER BY p.Score ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as HighestScoringPost,
        LAG(p.Score, 1) OVER (ORDER BY p.Score) as PreviousScore
    FROM Posts p
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 10 AND AVG(p.Score) > 5 THEN 'High Engagement'
            WHEN COUNT(DISTINCT p.Id) > 5 AND AVG(p.Score) > 2 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel,
        STRING_AGG(DISTINCT p.PostTypeId::text, ', ') as PostTypesUsed,
        STRING_AGG(DISTINCT v.VoteTypeId::text, ', ') as VoteTypesUsed,
        COUNT(DISTINCT p.Id) as PostsCreated,
        COUNT(DISTINCT v.Id) as VotesGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
ComplexQueryBase AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.UserTier,
        us.TotalScore,
        us.AvgScore,
        us.LastPostDate,
        CASE 
            WHEN us.PostCount > 0 THEN (us.TotalScore * 1.0 / us.PostCount)
            ELSE 0 
        END as AvgScorePerPost,
        tq.QuestionId,
        tq.Title as QuestionTitle,
        tq.Score as QuestionScore,
        tq.ViewCount as QuestionViewCount,
        tq.AnswerCount,
        tq.CommentCount as QuestionCommentCount,
        ta.TagName,
        ta.TagCount,
        ta.TagPopularity,
        pa.PostId,
        pa.Title as PostTitle,
        pa.Score as PostScore,
        pa.ActivityStatus,
        pa.DaysActive,
        pa.ScoreRankByType,
        pa.ScorePercentile,
        ue.EngagementLevel,
        ue.PostTypesUsed,
        ue.VoteTypesUsed,
        CASE 
            WHEN pa.ScoreRankByType <= 10 THEN 'Top 10 Scored'
            WHEN pa.ScoreRankByType <= 50 THEN 'Top 50 Scored'
            ELSE 'Other'
        END as ScoreCategory,
        COALESCE(SUBSTRING(ta.TagName, 1, 3) || '_' || CAST(us.PostCount AS TEXT), 'N/A') as TagScoreKey,
        ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY pa.Score DESC) as UserPostRank,
        ROW_NUMBER() OVER (ORDER BY ta.TagCount DESC) as TagRank,
        COUNT(*) OVER () as TotalUsers,
        AVG(pa.Score) OVER (PARTITION BY pa.PostTypeId) as TypeAvgScore,
        LAG(pa.Score, 1) OVER (ORDER BY pa.CreationDate) as PreviousPostScore,
        LEAD(pa.Score, 1) OVER (ORDER BY pa.CreationDate) as NextPostScore,
        NTILE(5) OVER (ORDER BY pa.Score) as ScoreQuintile,
        RANK() OVER (ORDER BY pa.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY pa.CreationDate DESC) as RecentRank,
        EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 AND p.Score > 100) as HasHighScoreQuestion,
        EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 2 AND p.Score > 50) as HasHighScoreAnswer,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.UserId AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.UserId AND v.VoteTypeId = 3) as DownvoteCount
    FROM UserStats us
    LEFT JOIN TopQuestions tq ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = tq.QuestionId)
    LEFT JOIN TagAnalysis ta ON ta.TagName IS NOT NULL
    LEFT JOIN PostActivity pa ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
    LEFT JOIN UserEngagement ue ON us.UserId = ue.UserId
),
FilteredResults AS (
    SELECT 
        *,
        CASE 
            WHEN UserTier = 'Elite' AND PostCount > 100 THEN 'Elite Power User'
            WHEN Reputation > 50000 AND AvgScorePerPost > 5 THEN 'Highly Active Elite'
            WHEN EngagementLevel = 'High Engagement' AND PostCount > 50 THEN 'Engagement Champion'
            ELSE 'Regular User'
        END as UserClassification,
        IIF(AvgScorePerPost >= 10, 100, IIF(AvgScorePerPost >= 5, 75, IIF(AvgScorePerPost >= 1, 50, 25))) as PerformanceRating,
        IIF(DaysActive > 365, 'Long Term', IIF(DaysActive > 30, 'Medium Term', 'Short Term')) as EngagementDuration,
        CONCAT(DisplayName, ' - ', UserTier, ' - ', EngagementLevel) as CompleteUserDescriptor,
        ROUND((TotalScore * 1.0 / NULLIF(Reputation, 0)) * 100, 2) as ScoreReputationRatio,
        NULLIF(CommentCount, 0) / NULLIF(PostCount, 0) as CommentPerPostRatio,
        IIF(COUNT(*) OVER (PARTITION BY TagPopularity) > 1, 1, 0) as MultipleTagsInCategory,
        ABS(Score - (SELECT AVG(Score) FROM Posts)) as ScoreDeviationFromMean,
        CASE 
            WHEN TagPopularity = 'Popular' AND TagCount > 1000 THEN 1000
            WHEN TagPopularity = 'Moderate' AND TagCount > 100 THEN 100
            WHEN TagPopularity = 'Niche' AND TagCount > 10 THEN 10
            ELSE 0
        END as PopularityScore
    FROM ComplexQueryBase
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    UserTier,
    TotalScore,
    AvgScore,
    AvgScorePerPost,
    QuestionScore,
    QuestionViewCount,
    AnswerCount,
    QuestionCommentCount,
    TagName,
    TagCount,
    TagPopularity,
    PostScore,
    ActivityStatus,
    DaysActive,
    ScoreRankByType,
    ScorePercentile,
    ScoreCategory,
    EngagementLevel,
    PostTypesUsed,
    VoteTypesUsed,
    UserClassification,
    PerformanceRating,
    EngagementDuration,
    CompleteUserDescriptor,
    ScoreReputationRatio,
    CommentPerPostRatio,
    MultipleTagsInCategory,
    ScoreDeviationFromMean,
    PopularityScore,
    ROW_NUMBER() OVER (ORDER BY PerformanceRating DESC, ScoreReputationRatio DESC) as OverallRank,
    COUNT(*) OVER () as TotalResults,
    AVG(ScoreReputationRatio) OVER () as AvgScoreReputationRatio,
    MIN(ScoreDeviationFromMean) OVER (PARTITION BY TagPopularity) as MinScoreDeviationByPopularity,
    MAX(PopularityScore) OVER (PARTITION BY PostTypeId) as MaxPopularityScoreByType,
    FIRST_VALUE(DisplayName) OVER (ORDER BY Reputation DESC) as TopReputationUser,
    NTH_VALUE(DisplayName, 3) OVER (ORDER BY Reputation DESC) as ThirdHighestUser,
    LAG(DisplayName, 1) OVER (ORDER BY Reputation DESC) as PreviousTopUser,
    LEAD(DisplayName, 1) OVER (ORDER BY Reputation DESC) as NextTopUser
FROM FilteredResults
WHERE PostCount > 0 
    AND (TagPopularity = 'Popular' OR TagPopularity = 'Moderate')
    AND (Score >= 10 OR Score IS NULL)
    AND NOT (UserTier = 'Member' AND PostCount < 5)
    AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.UserId = UserId AND ph.PostHistoryTypeId = 1)
ORDER BY PerformanceRating DESC, ScoreReputationRatio DESC, TagCount DESC
LIMIT 1000
OFFSET 500;