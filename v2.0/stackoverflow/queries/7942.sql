-- {"query": "7942.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 5137}
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) AS ScoreViewSum,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Question without Answers'
            ELSE 'Other'
        END AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        NTILE(10) OVER (ORDER BY p.Score) AS ScoreDecile,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
        MAX(p.Score) OVER (PARTITION BY p.OwnerUserId) AS MaxScorePerUser,
        MIN(p.Score) OVER (PARTITION BY p.OwnerUserId) AS MinScorePerUser,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS CumulativeScore,
        ABS(p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) AS ScoreChange,
        CASE 
            WHEN p.ViewCount IS NULL OR p.ViewCount < 0 THEN 0 
            ELSE p.ViewCount 
        END AS SafeViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(SUM(ps.Score), 0) AS TotalScore,
        COALESCE(COUNT(ps.Id), 0) AS TotalPosts,
        COALESCE(MAX(ps.Score), 0) AS MaxPostScore,
        COALESCE(AVG(ps.Score), 0) AS AvgPostScore,
        COALESCE(SUM(ps.SafeViewCount), 0) AS TotalViews,
        COALESCE(SUM(ps.AnswerCount), 0) AS TotalAnswers,
        RANK() OVER (ORDER BY COALESCE(SUM(ps.Score), 0) DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY COALESCE(COUNT(ps.Id), 0) DESC) AS PostRank
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
QuestionStats AS (
    SELECT 
        ps.Id AS QuestionId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.Title,
        ps.Tags,
        ps.CreationDate,
        CASE WHEN ps.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS AcceptanceFlag,
        CASE 
            WHEN ps.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
            WHEN ps.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        ps.ScoreViewSum,
        ps.ScoreChange,
        ps.ScoreDecile,
        ps.UserPostRank,
        ps.PrevScore,
        ps.NextScore,
        ps.TotalPostsByUser,
        ps.AvgScorePerUser,
        ps.MaxScorePerUser,
        ps.MinScorePerUser,
        ps.CumulativeScore
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        ps.Id AS AnswerId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.ParentId,
        ps.Title,
        ps.Tags,
        ps.ScoreViewSum,
        ps.ScoreChange,
        ps.ScoreDecile,
        ps.UserPostRank,
        ps.PrevScore,
        ps.NextScore,
        ps.TotalPostsByUser,
        ps.AvgScorePerUser,
        ps.MaxScorePerUser,
        ps.MinScorePerUser,
        ps.CumulativeScore,
        CASE WHEN ps.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS AcceptanceFlag
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
),
AggregatedData AS (
    SELECT 
        qs.QuestionId,
        qs.OwnerUserId,
        qs.Score AS QuestionScore,
        qs.ViewCount AS QuestionViewCount,
        qs.AnswerCount AS QuestionAnswerCount,
        qs.CommentCount AS QuestionCommentCount,
        qs.FavoriteCount AS QuestionFavoriteCount,
        qs.Title AS QuestionTitle,
        qs.Tags AS QuestionTags,
        qs.CreationDate AS QuestionCreationDate,
        qs.QuestionStatus,
        qs.AcceptanceFlag,
        qs.ScoreViewSum AS QuestionScoreViewSum,
        qs.ScoreChange AS QuestionScoreChange,
        qs.ScoreDecile AS QuestionScoreDecile,
        qs.UserPostRank AS QuestionUserPostRank,
        qs.PrevScore AS QuestionPrevScore,
        qs.NextScore AS QuestionNextScore,
        qs.TotalPostsByUser AS QuestionTotalPostsByUser,
        qs.AvgScorePerUser AS QuestionAvgScorePerUser,
        qs.MaxScorePerUser AS QuestionMaxScorePerUser,
        qs.MinScorePerUser AS QuestionMinScorePerUser,
        qs.CumulativeScore AS QuestionCumulativeScore,
        asa.AnswerId,
        asa.Score AS AnswerScore,
        asa.ViewCount AS AnswerViewCount,
        asa.AnswerCount AS AnswerAnswerCount,
        asa.CommentCount AS AnswerCommentCount,
        asa.FavoriteCount AS AnswerFavoriteCount,
        asa.CreationDate AS AnswerCreationDate,
        asa.ParentId,
        asa.ScoreViewSum AS AnswerScoreViewSum,
        asa.ScoreChange AS AnswerScoreChange,
        asa.ScoreDecile AS AnswerScoreDecile,
        asa.UserPostRank AS AnswerUserPostRank,
        asa.PrevScore AS AnswerPrevScore,
        asa.NextScore AS AnswerNextScore,
        asa.TotalPostsByUser AS AnswerTotalPostsByUser,
        asa.AvgScorePerUser AS AnswerAvgScorePerUser,
        asa.MaxScorePerUser AS AnswerMaxScorePerUser,
        asa.MinScorePerUser AS AnswerMinScorePerUser,
        asa.CumulativeScore AS AnswerCumulativeScore
    FROM QuestionStats qs
    FULL OUTER JOIN AnswerStats asa ON qs.OwnerUserId = asa.OwnerUserId
),
RankedList AS (
    SELECT 
        ad.QuestionId,
        ad.OwnerUserId,
        ad.QuestionScore,
        ad.QuestionViewCount,
        ad.QuestionAnswerCount,
        ad.QuestionCommentCount,
        ad.QuestionFavoriteCount,
        ad.QuestionTitle,
        ad.QuestionTags,
        ad.QuestionCreationDate,
        ad.QuestionStatus,
        ad.AcceptanceFlag,
        ad.QuestionScoreViewSum,
        ad.QuestionScoreChange,
        ad.QuestionScoreDecile,
        ad.QuestionUserPostRank,
        ad.QuestionPrevScore,
        ad.QuestionNextScore,
        ad.QuestionTotalPostsByUser,
        ad.QuestionAvgScorePerUser,
        ad.QuestionMaxScorePerUser,
        ad.QuestionMinScorePerUser,
        ad.QuestionCumulativeScore,
        ad.AnswerId,
        ad.AnswerScore,
        ad.AnswerViewCount,
        ad.AnswerAnswerCount,
        ad.AnswerCommentCount,
        ad.AnswerFavoriteCount,
        ad.AnswerCreationDate,
        ad.ParentId,
        ad.AnswerScoreViewSum,
        ad.AnswerScoreChange,
        ad.AnswerScoreDecile,
        ad.AnswerUserPostRank,
        ad.AnswerPrevScore,
        ad.AnswerNextScore,
        ad.AnswerTotalPostsByUser,
        ad.AnswerAvgScorePerUser,
        ad.AnswerMaxScorePerUser,
        ad.AnswerMinScorePerUser,
        ad.AnswerCumulativeScore,
        CASE 
            WHEN ad.QuestionScore > 0 AND ad.AnswerScore > 0 THEN (ad.QuestionScore + ad.AnswerScore) / 2.0
            WHEN ad.QuestionScore > 0 THEN ad.QuestionScore
            WHEN ad.AnswerScore > 0 THEN ad.AnswerScore
            ELSE 0
        END AS CompositeScore,
        ROW_NUMBER() OVER (ORDER BY 
            CASE 
                WHEN ad.QuestionScore > 0 AND ad.AnswerScore > 0 THEN (ad.QuestionScore + ad.AnswerScore) / 2.0
                WHEN ad.QuestionScore > 0 THEN ad.QuestionScore
                WHEN ad.AnswerScore > 0 THEN ad.AnswerScore
                ELSE 0
            END DESC
        ) AS OverallRank,
        RANK() OVER (PARTITION BY ad.OwnerUserId ORDER BY 
            CASE 
                WHEN ad.QuestionScore > 0 AND ad.AnswerScore > 0 THEN (ad.QuestionScore + ad.AnswerScore) / 2.0
                WHEN ad.QuestionScore > 0 THEN ad.QuestionScore
                WHEN ad.AnswerScore > 0 THEN ad.AnswerScore
                ELSE 0
            END DESC
        ) AS UserRank
    FROM AggregatedData ad
),
FilteredResults AS (
    SELECT 
        rl.QuestionId,
        rl.OwnerUserId,
        rl.QuestionScore,
        rl.QuestionViewCount,
        rl.QuestionAnswerCount,
        rl.QuestionCommentCount,
        rl.QuestionFavoriteCount,
        rl.QuestionTitle,
        rl.QuestionTags,
        rl.QuestionCreationDate,
        rl.QuestionStatus,
        rl.AcceptanceFlag,
        rl.QuestionScoreViewSum,
        rl.QuestionScoreChange,
        rl.QuestionScoreDecile,
        rl.QuestionUserPostRank,
        rl.QuestionPrevScore,
        rl.QuestionNextScore,
        rl.QuestionTotalPostsByUser,
        rl.QuestionAvgScorePerUser,
        rl.QuestionMaxScorePerUser,
        rl.QuestionMinScorePerUser,
        rl.QuestionCumulativeScore,
        rl.AnswerId,
        rl.AnswerScore,
        rl.AnswerViewCount,
        rl.AnswerAnswerCount,
        rl.AnswerCommentCount,
        rl.AnswerFavoriteCount,
        rl.AnswerCreationDate,
        rl.ParentId,
        rl.AnswerScoreViewSum,
        rl.AnswerScoreChange,
        rl.AnswerScoreDecile,
        rl.AnswerUserPostRank,
        rl.AnswerPrevScore,
        rl.AnswerNextScore,
        rl.AnswerTotalPostsByUser,
        rl.AnswerAvgScorePerUser,
        rl.AnswerMaxScorePerUser,
        rl.AnswerMinScorePerUser,
        rl.AnswerCumulativeScore,
        rl.CompositeScore,
        rl.OverallRank,
        rl.UserRank,
        CASE WHEN rl.QuestionId IS NOT NULL THEN 'Question' ELSE 'Answer' END AS ItemType,
        CASE 
            WHEN rl.QuestionScore > rl.QuestionPrevScore AND rl.QuestionNextScore > rl.QuestionScore THEN 'Increasing'
            WHEN rl.QuestionScore < rl.QuestionPrevScore AND rl.QuestionNextScore < rl.QuestionScore THEN 'Decreasing'
            ELSE 'Stable'
        END AS Trend,
        CASE 
            WHEN rl.QuestionScore > 50 AND rl.QuestionTags LIKE '%sql%' THEN 'SQL High Score Question'
            WHEN rl.QuestionScore > 50 THEN 'High Score Question'
            WHEN rl.QuestionScore < 20 THEN 'Low Score Question'
            ELSE 'Moderate Score Question'
        END AS QuestionClassification,
        CASE 
            WHEN rl.AnswerScore > 25 THEN 'High Score Answer'
            WHEN rl.AnswerScore < 10 THEN 'Low Score Answer'
            ELSE 'Moderate Score Answer'
        END AS AnswerClassification
    FROM RankedList rl
    WHERE rl.QuestionScore IS NOT NULL OR rl.AnswerScore IS NOT NULL
),
TopPosts AS (
    SELECT 
        fr.QuestionId,
        fr.OwnerUserId,
        fr.QuestionScore,
        fr.QuestionViewCount,
        fr.QuestionAnswerCount,
        fr.QuestionCommentCount,
        fr.QuestionFavoriteCount,
        fr.QuestionTitle,
        fr.QuestionTags,
        fr.QuestionCreationDate,
        fr.QuestionStatus,
        fr.AcceptanceFlag,
        fr.QuestionScoreViewSum,
        fr.QuestionScoreChange,
        fr.QuestionScoreDecile,
        fr.QuestionUserPostRank,
        fr.QuestionPrevScore,
        fr.QuestionNextScore,
        fr.QuestionTotalPostsByUser,
        fr.QuestionAvgScorePerUser,
        fr.QuestionMaxScorePerUser,
        fr.QuestionMinScorePerUser,
        fr.QuestionCumulativeScore,
        fr.AnswerId,
        fr.AnswerScore,
        fr.AnswerViewCount,
        fr.AnswerAnswerCount,
        fr.AnswerCommentCount,
        fr.AnswerFavoriteCount,
        fr.AnswerCreationDate,
        fr.ParentId,
        fr.AnswerScoreViewSum,
        fr.AnswerScoreChange,
        fr.AnswerScoreDecile,
        fr.AnswerUserPostRank,
        fr.AnswerPrevScore,
        fr.AnswerNextScore,
        fr.AnswerTotalPostsByUser,
        fr.AnswerAvgScorePerUser,
        fr.AnswerMaxScorePerUser,
        fr.AnswerMinScorePerUser,
        fr.AnswerCumulativeScore,
        fr.CompositeScore,
        fr.OverallRank,
        fr.UserRank,
        fr.ItemType,
        fr.Trend,
        fr.QuestionClassification,
        fr.AnswerClassification,
        CASE 
            WHEN fr.QuestionScore > fr.QuestionAvgScorePerUser THEN 'Above Average Question'
            WHEN fr.QuestionScore < fr.QuestionAvgScorePerUser THEN 'Below Average Question'
            ELSE 'Average Question'
        END AS QuestionPerformance,
        CASE 
            WHEN fr.AnswerScore > fr.AnswerAvgScorePerUser THEN 'Above Average Answer'
            WHEN fr.AnswerScore < fr.AnswerAvgScorePerUser THEN 'Below Average Answer'
            ELSE 'Average Answer'
        END AS AnswerPerformance,
        CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - fr.QuestionCreationDate)) / 86400) AS INTEGER) AS DaysSinceCreation,
        COALESCE(fr.QuestionScoreViewSum, 0) + COALESCE(fr.AnswerScoreViewSum, 0) AS TotalScoreViewSum,
        CASE 
            WHEN fr.QuestionTags IS NOT NULL THEN 
                (SELECT COUNT(*) FROM (
                    SELECT TRIM(tagvals.t) AS val FROM (
                        SELECT
                            CASE
                                WHEN POSITION('<' IN fr.QuestionTags) = 0 THEN fr.QuestionTags
                                ELSE SUBSTRING(fr.QuestionTags FROM POSITION('<' IN fr.QuestionTags))
                            END AS t
                    ) tagvals
                ) tv WHERE tv.val != '')
            ELSE 0 
        END AS TagCount,
        CASE 
            WHEN (fr.QuestionScore IS NOT NULL) THEN 
                (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = fr.QuestionId AND ph.PostHistoryTypeId = 4)
            ELSE 0 
        END AS EditedQuestions,
        CASE 
            WHEN (fr.AnswerScore IS NOT NULL) THEN 
                (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = fr.AnswerId AND ph.PostHistoryTypeId = 5)
            ELSE 0 
        END AS EditedAnswers
    FROM FilteredResults fr
),
FinalAggregation AS (
    SELECT 
        tp.QuestionId,
        tp.OwnerUserId,
        tp.QuestionScore,
        tp.QuestionViewCount,
        tp.QuestionAnswerCount,
        tp.QuestionCommentCount,
        tp.QuestionFavoriteCount,
        tp.QuestionTitle,
        tp.QuestionTags,
        tp.QuestionCreationDate,
        tp.QuestionStatus,
        tp.AcceptanceFlag,
        tp.QuestionScoreViewSum,
        tp.QuestionScoreChange,
        tp.QuestionScoreDecile,
        tp.QuestionUserPostRank,
        tp.QuestionPrevScore,
        tp.QuestionNextScore,
        tp.QuestionTotalPostsByUser,
        tp.QuestionAvgScorePerUser,
        tp.QuestionMaxScorePerUser,
        tp.QuestionMinScorePerUser,
        tp.QuestionCumulativeScore,
        tp.AnswerId,
        tp.AnswerScore,
        tp.AnswerViewCount,
        tp.AnswerAnswerCount,
        tp.AnswerCommentCount,
        tp.AnswerFavoriteCount,
        tp.AnswerCreationDate,
        tp.ParentId,
        tp.AnswerScoreViewSum,
        tp.AnswerScoreChange,
        tp.AnswerScoreDecile,
        tp.AnswerUserPostRank,
        tp.AnswerPrevScore,
        tp.AnswerNextScore,
        tp.AnswerTotalPostsByUser,
        tp.AnswerAvgScorePerUser,
        tp.AnswerMaxScorePerUser,
        tp.AnswerMinScorePerUser,
        tp.AnswerCumulativeScore,
        tp.CompositeScore,
        tp.OverallRank,
        tp.UserRank,
        tp.ItemType,
        tp.Trend,
        tp.QuestionClassification,
        tp.AnswerClassification,
        tp.QuestionPerformance,
        tp.AnswerPerformance,
        tp.DaysSinceCreation,
        tp.TotalScoreViewSum,
        tp.TagCount,
        tp.EditedQuestions,
        tp.EditedAnswers,
        CASE 
            WHEN tp.CompositeScore > 50 THEN 
                CASE 
                    WHEN tp.QuestionScore > 0 THEN 'High Score Question'
                    WHEN tp.AnswerScore > 0 THEN 'High Score Answer'
                    ELSE 'Unknown'
                END
            WHEN tp.CompositeScore BETWEEN 20 AND 50 THEN 
                CASE 
                    WHEN tp.QuestionScore > 0 THEN 'Medium Score Question'
                    WHEN tp.AnswerScore > 0 THEN 'Medium Score Answer'
                    ELSE 'Unknown'
                END
            ELSE 
                CASE 
                    WHEN tp.QuestionScore > 0 THEN 'Low Score Question'
                    WHEN tp.AnswerScore > 0 THEN 'Low Score Answer'
                    ELSE 'Unknown'
                END
        END AS CompositeScoreClassification,
        CASE 
            WHEN tp.QuestionStatus = 'Answered' OR tp.QuestionStatus = 'Answer Accepted' THEN 'Active' 
            ELSE 'Inactive'
        END AS QuestionActivityStatus,
        CASE 
            WHEN tp.QuestionScore > 50 AND tp.QuestionAnswerCount > 3 THEN 'Popular'
            WHEN tp.QuestionScore > 50 THEN 'Upvoted'
            WHEN tp.QuestionAnswerCount > 3 THEN 'Answered'
            ELSE 'Regular'
        END AS QuestionPopularity,
        CASE 
            WHEN tp.AnswerScore > 10 THEN 'Valuable'
            WHEN tp.AnswerScore > 5 THEN 'Helpful'
            WHEN tp.AnswerScore > 0 THEN 'Basic'
            ELSE 'Low Value'
        END AS AnswerValue
    FROM TopPosts tp
)
SELECT 
    fa.QuestionId,
    fa.OwnerUserId,
    fa.QuestionScore,
    fa.QuestionViewCount,
    fa.QuestionAnswerCount,
    fa.QuestionCommentCount,
    fa.QuestionFavoriteCount,
    fa.QuestionTitle,
    fa.QuestionTags,
    fa.QuestionCreationDate,
    fa.QuestionStatus,
    fa.AcceptanceFlag,
    fa.QuestionScoreViewSum,
    fa.QuestionScoreChange,
    fa.QuestionScoreDecile,
    fa.QuestionUserPostRank,
    fa.QuestionPrevScore,
    fa.QuestionNextScore,
    fa.QuestionTotalPostsByUser,
    fa.QuestionAvgScorePerUser,
    fa.QuestionMaxScorePerUser,
    fa.QuestionMinScorePerUser,
    fa.QuestionCumulativeScore,
    fa.AnswerId,
    fa.AnswerScore,
    fa.AnswerViewCount,
    fa.AnswerAnswerCount,
    fa.AnswerCommentCount,
    fa.AnswerFavoriteCount,
    fa.AnswerCreationDate,
    fa.ParentId,
    fa.AnswerScoreViewSum,
    fa.AnswerScoreChange,
    fa.AnswerScoreDecile,
    fa.AnswerUserPostRank,
    fa.AnswerPrevScore,
    fa.AnswerNextScore,
    fa.AnswerTotalPostsByUser,
    fa.AnswerAvgScorePerUser,
    fa.AnswerMaxScorePerUser,
    fa.AnswerMinScorePerUser,
    fa.AnswerCumulativeScore,
    fa.CompositeScore,
    fa.OverallRank,
    fa.UserRank,
    fa.ItemType,
    fa.Trend,
    fa.QuestionClassification,
    fa.AnswerClassification,
    fa.QuestionPerformance,
    fa.AnswerPerformance,
    fa.DaysSinceCreation,
    fa.TotalScoreViewSum,
    fa.TagCount,
    fa.EditedQuestions,
    fa.EditedAnswers,
    fa.CompositeScoreClassification,
    fa.QuestionActivityStatus,
    fa.QuestionPopularity,
    fa.AnswerValue,
    CASE 
        WHEN fa.QuestionScore > fa.QuestionAvgScorePerUser THEN 1 
        ELSE 0 
    END AS IsQuestionAboveAvg,
    CASE 
        WHEN fa.AnswerScore > fa.AnswerAvgScorePerUser THEN 1 
        ELSE 0 
    END AS IsAnswerAboveAvg,
    CASE 
        WHEN fa.QuestionScore > 0 OR fa.AnswerScore > 0 THEN 1 
        ELSE 0 
    END AS HasScore,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.QuestionTitle LIKE '%SQL%' THEN 1 
        ELSE 0 
    END AS IsSQLQuestion,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.QuestionAnswerCount > 0 THEN 1 
        ELSE 0 
    END AS HasAnswers,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.QuestionStatus = 'Answer Accepted' THEN 1 
        ELSE 0 
    END AS IsAcceptedAnswer,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.QuestionScore > fa.QuestionPrevScore AND fa.QuestionNextScore > fa.QuestionScore THEN 1 
        WHEN fa.AnswerId IS NOT NULL AND fa.AnswerScore > fa.AnswerPrevScore AND fa.AnswerNextScore > fa.AnswerScore THEN 1 
        ELSE 0 
    END AS IsIncreasingScore,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.TagCount > 2 THEN 1 
        ELSE 0 
    END AS HasMultipleTags,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.DaysSinceCreation > 30 THEN 1 
        ELSE 0 
    END AS IsOldPost,
    CASE 
        WHEN fa.CompositeScore > 100 THEN 'Very High'
        WHEN fa.CompositeScore > 50 THEN 'High'
        WHEN fa.CompositeScore > 10 THEN 'Medium'
        ELSE 'Low'
    END AS OverallScoreLevel,
    CASE 
        WHEN fa.QuestionId IS NOT NULL AND fa.QuestionScore > 100 THEN 1 
        ELSE 0 
    END AS IsHighScoreQuestion,
    CASE 
        WHEN fa.AnswerId IS NOT NULL AND fa.AnswerScore > 25 THEN 1 
        ELSE 0 
    END AS IsHighScoreAnswer,
    CASE 
        WHEN fa.QuestionId IS NOT NULL THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fa.QuestionId) 
        ELSE 0 
    END AS QuestionVoteCount,
    CASE 
        WHEN fa.AnswerId IS NOT NULL THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fa.AnswerId) 
        ELSE 0 
    END AS AnswerVoteCount,
    CASE 
        WHEN fa.QuestionId IS NOT NULL THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fa.QuestionId) 
        ELSE 0 
    END AS QuestionCommentCount,
    CASE 
        WHEN fa.AnswerId IS NOT NULL THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fa.AnswerId) 
        ELSE 0 
    END AS AnswerCommentCount,
    CASE 
        WHEN fa.QuestionId IS NOT NULL THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = fa.QuestionId) 
        ELSE 0 
    END AS QuestionLinkCount,
    CASE 
        WHEN fa.AnswerId IS NOT NULL THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = fa.AnswerId) 
        ELSE 0 
    END AS AnswerLinkCount
FROM FinalAggregation fa
WHERE fa.CompositeScore > 0
ORDER BY fa.CompositeScore DESC, fa.OverallRank ASC
LIMIT 1000;