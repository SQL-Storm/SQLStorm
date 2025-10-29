-- {"query": "7516.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2063} 
WITH UserActivityStats AS (
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
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        UpVotes,
        DownVotes,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        LastPostDate,
        AvgPostScore,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) as Ranking
    FROM UserActivityStats
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Answer'
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 'Answer to Question'
            ELSE 'Other'
        END as PostCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.ViewCount > 0 THEN (p.Score * 100.0 / p.ViewCount)
            ELSE 0
        END as ScorePerView,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.AnswerCount * 1.0 / p.ViewCount
            ELSE 0
        END as AnswersPerView,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(
                    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
                    0
                )
            ELSE 0
        END as UpvotesToQuestion,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(
                    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
                    0
                )
            ELSE 0
        END as DownvotesToQuestion,
        COALESCE(p.Tags, '') as Tags,
        COALESCE(
            (SELECT STRING_AGG(v.Comment, ', ') 
             FROM PostHistory v 
             WHERE v.PostId = p.Id 
             AND v.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
             AND v.Text IS NOT NULL), 
            'No History'
        ) as HistorySummary
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2010-01-01'
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
PostStatsWithRanking AS (
    SELECT 
        pp.*,
        ROW_NUMBER() OVER (ORDER BY pp.Score DESC, pp.ViewCount DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY pp.ViewCount DESC, pp.Score DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY pp.Score) as ScorePercentile,
        PERCENT_RANK() OVER (ORDER BY pp.ViewCount) as ViewPercentile
    FROM PostPerformance pp
),
FilteredPosts AS (
    SELECT 
        ps.*,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStatsWithRanking) THEN 'Above Average'
            WHEN ps.Score < (SELECT AVG(Score) FROM PostStatsWithRanking) THEN 'Below Average'
            ELSE 'Average'
        END as ScoreStatus,
        CASE 
            WHEN ps.ViewCount > (SELECT AVG(ViewCount) FROM PostStatsWithRanking) THEN 'Above Average Views'
            WHEN ps.ViewCount < (SELECT AVG(ViewCount) FROM PostStatsWithRanking) THEN 'Below Average Views'
            ELSE 'Average Views'
        END as ViewStatus,
        CASE 
            WHEN ps.ViewCount > 100 THEN 'Popular'
            WHEN ps.ViewCount > 50 THEN 'Moderately Popular'
            WHEN ps.ViewCount > 10 THEN 'Low View Count'
            ELSE 'Very Low'
        END as PopularityCategory
    FROM PostStatsWithRanking ps
),
FinalAnalysis AS (
    SELECT 
        fp.*,
        tu.DisplayName as TopUser,
        tu.Ranking as TopUserRanking,
        CASE 
            WHEN fp.ScorePercentile >= 0.9 THEN 'Top 10%'
            WHEN fp.ScorePercentile >= 0.75 THEN 'Top 25%'
            WHEN fp.ScorePercentile >= 0.5 THEN 'Top 50%'
            ELSE 'Below Average'
        END as ScorePerformanceCategory,
        CASE 
            WHEN fp.ViewPercentile >= 0.9 THEN 'Top 10% Viewers'
            WHEN fp.ViewPercentile >= 0.75 THEN 'Top 25% Viewers'
            WHEN fp.ViewPercentile >= 0.5 THEN 'Top 50% Viewers'
            ELSE 'Below Average Viewers'
        END as ViewPerformanceCategory,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = fp.PostId 
             AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
             AND ph.CreationDate > fp.CreationDate), 
            0
        ) as EditCount,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = fp.PostId 
             AND v.VoteTypeId = 5), 
            0
        ) as FavoriteCount,
        CASE 
            WHEN fp.Score > 100 THEN 'Highly Rated'
            WHEN fp.Score > 50 THEN 'Moderately Rated'
            WHEN fp.Score > 10 THEN 'Low Rated'
            ELSE 'Very Low'
        END as RatingCategory,
        CASE 
            WHEN fp.LastActivityDate > DATEADD(day, -7, GETDATE()) THEN 'Recently Active'
            WHEN fp.LastActivityDate > DATEADD(day, -30, GETDATE()) THEN 'Active in Month'
            WHEN fp.LastActivityDate > DATEADD(day, -90, GETDATE()) THEN 'Active in Quarter'
            ELSE 'Inactive'
        END as ActivityStatus,
        CASE 
            WHEN fp.ParentId IS NOT NULL THEN 1
            ELSE 0
        END as IsAnswer,
        CASE 
            WHEN fp.PostTypeId = 1 THEN 'Question'
            WHEN fp.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        RANK() OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.CreationDate) as UserPostSequence
    FROM FilteredPosts fp
    LEFT JOIN TopUsers tu ON fp.OwnerUserId = tu.UserId
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.OwnerName,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.ScorePerView,
    fa.AnswersPerView,
    fa.ScoreStatus,
    fa.ViewStatus,
    fa.ScorePerformanceCategory,
    fa.ViewPerformanceCategory,
    fa.PopularityCategory,
    fa.RatingCategory,
    fa.ActivityStatus,
    fa.PostType,
    fa.EditCount,
    fa.TopUserRanking,
    fa.UserPostSequence,
    CASE 
        WHEN fa.Score > 100 AND fa.ViewCount > 100 THEN 'High Impact'
        WHEN fa.Score > 50 OR fa.ViewCount > 50 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END as ImpactLevel,
    CASE 
        WHEN fa.Score > (SELECT AVG(Score) FROM FinalAnalysis) THEN 
            (fa.Score - (SELECT AVG(Score) FROM FinalAnalysis)) / 
            (SELECT STDEV(Score) FROM FinalAnalysis)
        ELSE 0
    END as StandardizedScore,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = fa.PostId), 0) as ActualComments,
    fa.HistorySummary,
    fa.AllTags
FROM FinalAnalysis fa
WHERE fa.Score > 0 
  AND fa.AnswerCount >= 0
ORDER BY fa.Score DESC, fa.ViewCount DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;