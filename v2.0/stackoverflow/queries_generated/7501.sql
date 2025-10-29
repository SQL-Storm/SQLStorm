-- {"query": "7501.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2465} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(100) OVER (ORDER BY p.ViewCount DESC) as ViewQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostStats AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.UserPostRank,
        rp.ScoreRank,
        rp.ViewQuartile,
        LAG(rp.Score, 1) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) as PrevScore,
        LAG(rp.ViewCount, 1) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) as PrevViewCount,
        LEAD(rp.Score, 1) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) as NextScore,
        COALESCE(rp.AnswerCount, 0) + COALESCE(rp.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN rp.Score > 100 THEN 'High'
            WHEN rp.Score > 50 THEN 'Medium'
            WHEN rp.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreCategory,
        CASE 
            WHEN rp.ViewCount > 1000 THEN 'Viral'
            WHEN rp.ViewCount > 500 THEN 'Popular'
            WHEN rp.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Obscure'
        END as PopularityLevel,
        DATEDIFF('day', rp.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        CAST(rp.Score AS FLOAT) / NULLIF(rp.ViewCount, 0) as ScoreToViewRatio
    FROM RankedPosts rp
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) as TotalPosts,
        AVG(ps.Score) as AvgScore,
        MAX(ps.Score) as MaxScore,
        SUM(ps.ViewCount) as TotalViews,
        SUM(ps.CommentCount) as TotalComments,
        SUM(ps.AnswerCount) as TotalAnswers,
        AVG(ps.AnswerCount) as AvgAnswers,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) as Answers
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.Title, 'No Question') as QuestionTitle,
        COALESCE(p2.Title, 'No Wiki') as WikiTitle,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularRank
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
),
ComplexMetrics AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ViewQuartile,
        ps.PrevScore,
        ps.PrevViewCount,
        ps.NextScore,
        ps.EngagementCount,
        ps.ScoreCategory,
        ps.PopularityLevel,
        ps.AgeInDays,
        ps.ScoreToViewRatio,
        ua.Reputation,
        ua.DisplayName,
        ua.Views as UserViews,
        ua.TotalPosts,
        ua.AvgScore,
        ua.MaxScore,
        ua.TotalViews,
        ua.TotalComments,
        ua.TotalAnswers,
        ua.AvgAnswers,
        ua.Questions,
        ua.Answers,
        ta.TagName,
        ta.Count as TagCount,
        ta.TagPopularity,
        ta.PopularRank,
        CASE 
            WHEN ps.ScoreToViewRatio > 0.1 THEN 'High Engagement'
            WHEN ps.ScoreToViewRatio > 0.05 THEN 'Moderate Engagement'
            WHEN ps.ScoreToViewRatio > 0.01 THEN 'Low Engagement'
            ELSE 'Very Low Engagement'
        END as EngagementLevel,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.AnswerCount < 5 THEN 'Few Answers'
            WHEN ps.AnswerCount >= 5 AND ps.AnswerCount < 10 THEN 'Some Answers'
            WHEN ps.AnswerCount >= 10 THEN 'Many Answers'
            ELSE 'No Answers'
        END as AnswerLevel,
        CASE 
            WHEN ps.CommentCount > 10 THEN 'Highly Commented'
            WHEN ps.CommentCount > 5 THEN 'Moderately Commented'
            WHEN ps.CommentCount > 0 THEN 'Slightly Commented'
            ELSE 'No Comments'
        END as CommentLevel,
        CASE 
            WHEN ps.FavoriteCount > 100 THEN 'Highly Favorited'
            WHEN ps.FavoriteCount > 50 THEN 'Moderately Favorited'
            WHEN ps.FavoriteCount > 10 THEN 'Slightly Favorited'
            ELSE 'Not Favorited'
        END as FavoriteLevel,
        CASE 
            WHEN ps.AgeInDays < 30 THEN 'New'
            WHEN ps.AgeInDays < 180 THEN 'Medium Age'
            ELSE 'Established'
        END as PostAgeCategory,
        ps.AgeInDays - LAG(ps.AgeInDays, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as DaysBetweenPosts,
        ps.Score - LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as ScoreChange,
        ps.ViewCount - LAG(ps.ViewCount, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as ViewChange
    FROM PostStats ps
    JOIN UserEngagement ua ON ps.OwnerUserId = ua.UserId
    LEFT JOIN TagAnalysis ta ON ps.Tags LIKE '%' || ta.TagName || '%'
    WHERE ps.ViewCount > 0 AND ps.Score > -100
)
SELECT 
    cm.Id,
    cm.PostTypeId,
    cm.Score,
    cm.ViewCount,
    cm.CreationDate,
    cm.OwnerUserId,
    cm.Title,
    cm.Tags,
    cm.AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.UserPostRank,
    cm.ScoreRank,
    cm.ViewQuartile,
    cm.PrevScore,
    cm.PrevViewCount,
    cm.NextScore,
    cm.EngagementCount,
    cm.ScoreCategory,
    cm.PopularityLevel,
    cm.AgeInDays,
    cm.ScoreToViewRatio,
    cm.Reputation,
    cm.DisplayName,
    cm.Views as UserViews,
    cm.TotalPosts,
    cm.AvgScore,
    cm.MaxScore,
    cm.TotalViews,
    cm.TotalComments,
    cm.TotalAnswers,
    cm.AvgAnswers,
    cm.Questions,
    cm.Answers,
    cm.TagName,
    cm.TagCount,
    cm.TagPopularity,
    cm.PopularRank,
    cm.EngagementLevel,
    cm.AnswerLevel,
    cm.CommentLevel,
    cm.FavoriteLevel,
    cm.PostAgeCategory,
    cm.DaysBetweenPosts,
    cm.ScoreChange,
    cm.ViewChange,
    CASE 
        WHEN cm.Score > 0 AND cm.ViewCount > 0 THEN (
            (cm.Score + cm.AvgScore) / 
            NULLIF((cm.ViewCount + cm.TotalViews), 0)
        )
        ELSE 0
    END as EnhancedEngagementRatio,
    CASE 
        WHEN cm.AgeInDays > 0 AND cm.Score > 0 THEN 
            cm.TotalViews / cm.AgeInDays
        ELSE 0
    END as DailyViewRate,
    CASE 
        WHEN cm.AnswerCount > 0 AND cm.Score > 0 THEN 
            cm.AnswerCount / cm.Score
        ELSE 0
    END as AnswersPerScore,
    CASE 
        WHEN cm.CommentCount > 0 AND cm.Score > 0 THEN 
            cm.CommentCount * 100.0 / cm.Score
        ELSE 0
    END as CommentToScoreRatio,
    CASE 
        WHEN cm.FavoriteCount > 0 AND cm.Score > 0 THEN 
            cm.FavoriteCount / NULLIF(cm.Score, 0)
        ELSE 0
    END as FavoritesPerScore,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = cm.Id 
         AND c.CreationDate > cm.CreationDate 
         AND c.Score > 5), 0
    ) as RecentHighScoreComments,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = cm.Id 
         AND v.VoteTypeId = 2), 0
    ) as UpvotesCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = cm.Id 
         AND v.VoteTypeId = 3), 0
    ) as DownvotesCount,
    COALESCE(
        (SELECT AVG(v.Score) 
         FROM Votes v 
         WHERE v.PostId = cm.Id 
         AND v.VoteTypeId IN (2,3)), 0
    ) as AvgVoteScore,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.ParentId = cm.Id), 0
    ) as ChildPostsCount,
    CASE 
        WHEN cm.ViewCount > cm.UserViews THEN 'Above User Avg'
        WHEN cm.ViewCount = cm.UserViews THEN 'At User Avg'
        ELSE 'Below User Avg'
    END as ViewComparison,
    CASE 
        WHEN cm.Score > cm.AvgScore THEN 'Above Avg'
        WHEN cm.Score = cm.AvgScore THEN 'At Avg'
        ELSE 'Below Avg'
    END as ScoreComparison
FROM ComplexMetrics cm
WHERE cm.PostTypeId IN (1, 2)
AND cm.Score > 0
AND cm.ViewCount > 0
AND cm.AgeInDays >= 1
AND cm.TagName IS NOT NULL
ORDER BY cm.Score DESC, cm.ViewCount DESC
LIMIT 1000 OFFSET 0;