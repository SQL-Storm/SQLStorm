-- {"query": "7724.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2437} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_score,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
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
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastActivity,
        STRING_AGG(p.Tags, '; ') as AllTags,
        COUNT(DISTINCT b.Id) as BadgesCount,
        MAX(b.Date) as LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
ActivityMetrics AS (
    SELECT 
        ps.UserId,
        ps.DisplayName,
        ps.Reputation,
        ps.TotalPosts,
        ps.Questions,
        ps.Answers,
        ps.TotalScore,
        ps.AvgScore,
        ps.LastActivity,
        ps.AllTags,
        ps.BadgesCount,
        ps.LastBadgeDate,
        CASE 
            WHEN ps.TotalPosts > 0 THEN ps.TotalScore * 1.0 / ps.TotalPosts 
            ELSE 0 
        END as ScorePerPost,
        CASE 
            WHEN ps.Questions > 0 THEN ps.Answers * 1.0 / ps.Questions 
            ELSE 0 
        END as AnswersPerQuestion,
        DATEDIFF('day', ps.LastActivity, CURRENT_TIMESTAMP) as DaysSinceLastActivity,
        CASE 
            WHEN ps.Reputation >= 10000 THEN 'Expert'
            WHEN ps.Reputation >= 1000 THEN 'Intermediate'
            WHEN ps.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationLevel,
        CASE 
            WHEN ps.BadgesCount >= 50 THEN 'Master'
            WHEN ps.BadgesCount >= 20 THEN 'Veteran'
            WHEN ps.BadgesCount >= 5 THEN 'Enthusiast'
            ELSE 'Regular'
        END as BadgeLevel
    FROM UserStats ps
),
TopPosts AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.next_score,
        rp.moving_avg_score,
        rp.quartile,
        ROW_NUMBER() OVER (ORDER BY rp.Score DESC) as rank_by_score,
        DENSE_RANK() OVER (ORDER BY rp.OwnerUserId, rp.Score DESC) as user_rank_by_score
    FROM RankedPosts rp
    WHERE rp.rn <= 3
),
PostAnalysis AS (
    SELECT 
        tp.Id,
        tp.PostTypeId,
        tp.OwnerUserId,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.Title,
        tp.Tags,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.rn,
        tp.prev_score,
        tp.next_score,
        tp.moving_avg_score,
        tp.quartile,
        tp.rank_by_score,
        tp.user_rank_by_score,
        CASE 
            WHEN tp.moving_avg_score > 10 THEN 'Highly Active'
            WHEN tp.moving_avg_score > 5 THEN 'Moderately Active' 
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'Above Average'
            ELSE 'Below Average'
        END as ScoreLevel,
        TRIM(BOTH '<>' FROM tp.Tags) as CleanTags,
        ARRAY_LENGTH(string_to_array(TRIM(BOTH '<>' FROM tp.Tags), '><'), 1) as TagCount,
        COALESCE(tp.AnswerCount, 0) + COALESCE(tp.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN tp.Tags IS NOT NULL AND tp.Tags != '' THEN TRIM(BOTH '<>' FROM tp.Tags)
            ELSE 'No Tags'
        END as TagInfo,
        CASE 
            WHEN tp.CommentCount IS NULL OR tp.CommentCount = 0 THEN 'No Comments'
            WHEN tp.CommentCount < 5 THEN 'Few Comments'
            WHEN tp.CommentCount < 20 THEN 'Moderate Comments'
            ELSE 'Many Comments'
        END as CommentLevel,
        COALESCE(tp.ViewCount, 0) as AdjustedViews,
        GREATEST(COALESCE(tp.ViewCount, 0) - COALESCE(tp.Score, 0), 0) as ViewScoreDifference,
        COALESCE(tp.FavoriteCount, 0) as Favorites,
        CASE 
            WHEN tp.FavoriteCount IS NOT NULL AND tp.FavoriteCount > 0 THEN tp.FavoriteCount * 100.0 / NULLIF(tp.ViewCount, 0)
            ELSE 0 
        END as FavoriteToViewRatio,
        CASE 
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 0 THEN (tp.AnswerCount * 100.0 / NULLIF(tp.AnswerCount + tp.CommentCount, 0))
            ELSE 0 
        END as AnswerToCommentRatio
    FROM TopPosts tp
    WHERE tp.Score > 0
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT pa.OwnerUserId) as UniqueAuthors,
    AVG(pa.Score) as AvgScore,
    MAX(pa.Score) as MaxScore,
    MIN(pa.Score) as MinScore,
    SUM(pa.ViewCount) as TotalViews,
    AVG(pa.ViewCount) as AvgViews,
    COUNT(CASE WHEN pa.TagCount > 3 THEN 1 END) as HighTagCountPosts,
    COUNT(CASE WHEN pa.CommentLevel = 'Many Comments' THEN 1 END) as ManyCommentsPosts,
    COUNT(CASE WHEN pa.ActivityLevel = 'Highly Active' THEN 1 END) as HighlyActivePosts,
    STRING_AGG(DISTINCT COALESCE(pa.TagInfo, 'None'), ', ') as AllTagsUsed,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) as HighValueQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) as HighValueAnswers,
    COUNT(DISTINCT CASE WHEN pa.ScorePerPost > 5 THEN pa.OwnerUserId END) as HighScoringAuthors,
    COUNT(DISTINCT CASE WHEN pa.BadgeLevel = 'Master' THEN pa.UserId END) as MasterBadgeHolders,
    AVG(pa.FavoriteToViewRatio) as AvgFavoriteToViewRatio,
    STDEV(pa.Score) as ScoreStdDeviation,
    COUNT(DISTINCT CASE WHEN pa.AnswerToCommentRatio > 50 THEN pa.Id END) as HighAnswerCommentRatioPosts,
    (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE VoteTypeId = 2) as TotalUpvotes,
    (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE VoteTypeId = 3) as TotalDownvotes,
    (SELECT AVG(Score) FROM Votes WHERE VoteTypeId = 5) as AvgBountyAmount,
    COUNT(DISTINCT CASE WHEN pa.Score > 0 AND pa.TagCount > 0 THEN pa.Id END) as ScoredTaggedPosts,
    COUNT(DISTINCT CASE WHEN pa.Score > 100 THEN pa.Id END) as HighlyScoredPosts,
    DATEDIFF('day', MIN(pa.CreationDate), MAX(pa.CreationDate)) as ReportPeriodDays,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags != '') as TaggedQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND Tags IS NULL) as UntaggedAnswers,
    COUNT(DISTINCT CASE WHEN pa.ViewScoreDifference > 100 THEN pa.Id END) as ViewScoreDiffHigh,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > 1000) as HighViewPosts,
    COUNT(DISTINCT CASE WHEN pa.Favorites > 10 THEN pa.Id END) as HighlyFavoritedPosts,
    (SELECT COUNT(*) FROM Comments WHERE Length(Text) > 100) as LongComments,
    COUNT(DISTINCT CASE WHEN pa.AnswersPerQuestion > 0.5 THEN pa.OwnerUserId END) as ActiveAnswerers,
    COUNT(DISTINCT CASE WHEN pa.ScoreLevel = 'Above Average' THEN pa.Id END) as AboveAvgScorePosts,
    COUNT(DISTINCT CASE WHEN pa.ActivityLevel = 'Moderately Active' THEN pa.Id END) as ModerateActivityPosts,
    COUNT(DISTINCT CASE WHEN pa.ReputationLevel = 'Expert' THEN pa.UserId END) as ExpertUsers,
    COUNT(DISTINCT CASE WHEN pa.BadgeLevel = 'Veteran' THEN pa.UserId END) as VeteranUsers,
    COUNT(DISTINCT CASE WHEN pa.Score > 50 AND pa.ViewCount > 100 THEN pa.Id END) as TopPerformingPosts,
    COUNT(DISTINCT CASE WHEN pa.Score > 0 AND pa.ViewCount IS NOT NULL THEN pa.Id END) as ScoredViewedPosts,
    AVG(pa.AnswerToCommentRatio) as AvgAnswerToCommentRatio,
    (SELECT COUNT(*) FROM Posts WHERE LastEditDate IS NOT NULL) as EditedPosts,
    (SELECT COUNT(*) FROM Posts WHERE LastEditDate > CreationDate) as RecentlyEditedPosts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND AnswerCount > 0) as QuestionsWithAnswers,
    (SELECT COUNT(*) FROM Posts WHERE ParentId IS NOT NULL AND PostTypeId = 2) as AnsweredPosts,
    (SELECT COUNT(*) FROM Posts WHERE ContentLicense = 'CC BY-SA 3.0') as CC_BY_SA_3_0_Posts
FROM PostAnalysis pa
LEFT JOIN ActivityMetrics am ON pa.OwnerUserId = am.UserId
WHERE pa.OwnerUserId IS NOT NULL