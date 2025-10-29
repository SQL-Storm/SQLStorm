-- {"query": "7594.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2903} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) as TotalUpvotes,
        SUM(CASE WHEN p.Score < 0 THEN ABS(p.Score) ELSE 0 END) as TotalDownvotes,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Contributor'
            ELSE 'Member'
        END as ReputationLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as TotalAnswerViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostRankings AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) as RecentRank,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
QuestionStats AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.Tags,
        q.CreationDate,
        q.LastActivityDate,
        q.OwnerUserId,
        MAX(a.Score) as BestAnswerScore,
        COUNT(a.Id) as TotalAnswers,
        AVG(a.Score) as AverageAnswerScore,
        SUM(a.Score) as TotalAnswerPoints,
        MAX(a.CreationDate) as LatestAnswerDate,
        MIN(a.CreationDate) as FirstAnswerDate,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN DATEDIFF(CURRENT_TIMESTAMP, q.CreationDate) > 7 THEN 'Unanswered (Old)'
            ELSE 'Unanswered'
        END as QuestionStatus
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount, q.Tags, q.CreationDate, q.LastActivityDate, q.OwnerUserId, q.AcceptedAnswerId
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.LastEditDate,
        a.Body,
        a.CommentCount,
        DATEDIFF(CURRENT_TIMESTAMP, a.CreationDate) as DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as ScoreRankWithinQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END), 0) as TotalVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as Downvotes,
        COALESCE(COUNT(DISTINCT c.Id), 0) as CommentsMade,
        COALESCE(COUNT(DISTINCT ph.Id), 0) as PostEdits,
        COALESCE(COUNT(DISTINCT b.Id), 0) as BadgesEarned,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) as GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) as SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) as BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.TagBased = 1 AND b.Class = 1 THEN b.Name END, ', ') as TagBasedGoldBadges,
        STRING_AGG(DISTINCT CASE WHEN b.TagBased = 1 AND b.Class = 2 THEN b.Name END, ', ') as TagBasedSilverBadges,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) > 1000 THEN 'Active'
            WHEN COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) > 500 THEN 'Moderate'
            ELSE 'Passive'
        END as VotingActivityLevel
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexFiltering AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.FavoriteCount,
        qs.Tags,
        qs.CreationDate,
        qs.OwnerUserId,
        qs.BestAnswerScore,
        qs.TotalAnswers,
        qs.AverageAnswerScore,
        qs.TotalAnswerPoints,
        qs.LatestAnswerDate,
        qs.FirstAnswerDate,
        qs.QuestionStatus
    FROM QuestionStats qs
    WHERE qs.QuestionStatus IN ('Answered', 'Unanswered')
      AND qs.Score >= 5
      AND (qs.AnswerCount >= 1 OR qs.CommentCount >= 3)
      AND (qs.Tags IS NOT NULL AND qs.Tags != '')
      AND qs.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
),
FinalAggregation AS (
    SELECT 
        cf.QuestionId,
        cf.Title,
        cf.Score,
        cf.ViewCount,
        cf.AnswerCount,
        cf.CommentCount,
        cf.FavoriteCount,
        cf.Tags,
        cf.CreationDate,
        cf.OwnerUserId,
        cf.BestAnswerScore,
        cf.TotalAnswers,
        cf.AverageAnswerScore,
        cf.TotalAnswerPoints,
        cf.LatestAnswerDate,
        cf.FirstAnswerDate,
        cf.QuestionStatus,
        ps.ScoreRank,
        ps.ViewRank,
        ps.RecentRank,
        ps.AvgScoreByType,
        ps.ScorePercentile,
        ps.ScoreQuartile,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.Badges,
        us.TotalUpvotes,
        us.TotalDownvotes,
        us.ReputationLevel,
        us.TotalQuestionViews,
        us.TotalAnswerViews,
        ua.TotalVotes,
        ua.Upvotes,
        ua.Downvotes,
        ua.CommentsMade,
        ua.PostEdits,
        ua.BadgesEarned,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TagBasedGoldBadges,
        ua.TagBasedSilverBadges,
        ua.VotingActivityLevel,
        CASE 
            WHEN cf.QuestionStatus = 'Answered' AND cf.Score >= 10 THEN 'Highly Valued'
            WHEN cf.QuestionStatus = 'Answered' AND cf.Score >= 5 THEN 'Valued'
            WHEN cf.QuestionStatus = 'Unanswered' AND cf.ViewCount >= 100 THEN 'Popular Unanswered'
            ELSE 'Regular'
        END as QuestionClassification,
        CASE 
            WHEN cf.TotalAnswers >= 5 THEN 'High Engagement'
            WHEN cf.TotalAnswers >= 2 THEN 'Moderate Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel,
        COALESCE(ROUND((cf.CommentCount * 100.0 / NULLIF(cf.ViewCount, 0)), 2), 0) as CommentRate,
        COALESCE(ROUND((cf.FavoriteCount * 100.0 / NULLIF(cf.ViewCount, 0)), 2), 0) as FavoriteRate,
        COALESCE(ROUND((cf.BestAnswerScore / NULLIF(cf.TotalAnswerPoints, 0)), 3), 0) as BestAnswerRatio
    FROM ComplexFiltering cf
    LEFT JOIN PostRankings ps ON cf.QuestionId = ps.PostId
    LEFT JOIN UserStats us ON cf.OwnerUserId = us.UserId
    LEFT JOIN UserActivity ua ON cf.OwnerUserId = ua.UserId
    WHERE cf.Score > 0
)
SELECT 
    fa.QuestionId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.Tags,
    fa.CreationDate,
    fa.OwnerUserId,
    fa.BestAnswerScore,
    fa.TotalAnswers,
    fa.AverageAnswerScore,
    fa.TotalAnswerPoints,
    fa.LatestAnswerDate,
    fa.FirstAnswerDate,
    fa.QuestionStatus,
    fa.ScoreRank,
    fa.ViewRank,
    fa.RecentRank,
    fa.AvgScoreByType,
    fa.ScorePercentile,
    fa.ScoreQuartile,
    fa.TotalPosts,
    fa.Questions,
    fa.Answers,
    fa.Badges,
    fa.TotalUpvotes,
    fa.TotalDownvotes,
    fa.ReputationLevel,
    fa.TotalQuestionViews,
    fa.TotalAnswerViews,
    fa.TotalVotes,
    fa.Upvotes,
    fa.Downvotes,
    fa.CommentsMade,
    fa.PostEdits,
    fa.BadgesEarned,
    fa.GoldBadges,
    fa.SilverBadges,
    fa.BronzeBadges,
    fa.TagBasedGoldBadges,
    fa.TagBasedSilverBadges,
    fa.VotingActivityLevel,
    fa.QuestionClassification,
    fa.EngagementLevel,
    fa.CommentRate,
    fa.FavoriteRate,
    fa.BestAnswerRatio,
    CASE 
        WHEN fa.Score >= 100 THEN 'Legendary'
        WHEN fa.Score >= 50 THEN 'Master'
        WHEN fa.Score >= 25 THEN 'Expert'
        WHEN fa.Score >= 10 THEN 'Novice'
        ELSE 'Beginner'
    END as ScoreTier,
    ROW_NUMBER() OVER (ORDER BY fa.Score DESC, fa.ViewCount DESC) as OverallRank,
    PERCENT_RANK() OVER (ORDER BY fa.Score DESC) as ScoreRankPercent,
    DENSE_RANK() OVER (ORDER BY fa.ReputationLevel DESC, fa.Score DESC) as ReputationScoreRank,
    CASE 
        WHEN fa.Score > fa.AvgScoreByType THEN 'Above Average'
        WHEN fa.Score = fa.AvgScoreByType THEN 'Average'
        ELSE 'Below Average'
    END as ScoreComparison,
    CASE 
        WHEN LENGTH(fa.Tags) > 150 THEN 'Highly Tagged'
        WHEN LENGTH(fa.Tags) > 75 THEN 'Moderately Tagged'
        ELSE 'Low Tag Count'
    END as TagComplexity,
    EXTRACT(YEAR FROM fa.CreationDate) as CreationYear,
    EXTRACT(MONTH FROM fa.CreationDate) as CreationMonth,
    CASE 
        WHEN fa.CommentRate BETWEEN 0 AND 5 THEN 'Low Comments'
        WHEN fa.CommentRate BETWEEN 5 AND 15 THEN 'Medium Comments'
        WHEN fa.CommentRate > 15 THEN 'High Comments'
        ELSE 'No Comments'
    END as CommentIntensity
FROM FinalAggregation fa
WHERE fa.Score > 0
  AND fa.ViewCount > 0
  AND fa.TotalAnswers >= 0
  AND (fa.TagBasedGoldBadges IS NOT NULL OR fa.TagBasedSilverBadges IS NOT NULL)
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.RecentRank ASC, fa.QuestionId ASC
LIMIT 1000;