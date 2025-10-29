-- {"query": "7102.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4582} 
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
        COALESCE(p.AnswerCount, 0) AS AnswerCountCoalesced,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 100 THEN 'HighlyVotedQuestion'
            WHEN p.PostTypeId = 1 AND p.Score <= 100 THEN 'RegularQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 50 THEN 'HighlyVotedAnswer'
            WHEN p.PostTypeId = 2 AND p.Score <= 50 THEN 'RegularAnswer'
            ELSE 'Other'
        END AS PostCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS GlobalViewRank,
        NTILE(10) OVER (ORDER BY p.Score) AS ScoreDecile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(trim(p.Tags, '<'), '>'), '><')) AS tag)
            ELSE 0 
        END AS TagCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 100) THEN 'AnswerWithHighScore'
            ELSE 'Active'
        END AS Status,
        COALESCE(
            (SELECT SUM(v.BountyAmount) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 
            0
        ) AS TotalBounty,
        COALESCE(
            (SELECT AVG(v.BountyAmount) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId = 9), 
            0
        ) AS AverageBounty,
        COALESCE(p.Body, '') AS CleanBody,
        TRIM(LOWER(p.Title)) AS LowerTitle,
        CASE 
            WHEN LENGTH(p.Body) > 1000 THEN 'Long'
            WHEN LENGTH(p.Body) > 500 THEN 'Medium'
            WHEN LENGTH(p.Body) > 100 THEN 'Short'
            ELSE 'VeryShort'
        END AS BodyLengthCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPerformance AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS TotalAnswers,
        SUM(COALESCE(ps.Score, 0)) AS TotalScore,
        AVG(COALESCE(ps.Score, 0)) AS AverageScore,
        MAX(COALESCE(ps.Score, 0)) AS MaxScore,
        MIN(COALESCE(ps.Score, 0)) AS MinScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(ps.Score, 0)) AS MedianScore,
        STRING_AGG(ps.Title, ', ') AS AllTitles,
        COUNT(DISTINCT ps.AnswerCountCoalesced) AS UniqueAnswerCounts,
        SUM(CASE WHEN ps.Status = 'Closed' THEN 1 ELSE 0 END) AS ClosedPosts,
        SUM(CASE WHEN ps.Status = 'CommunityOwned' THEN 1 ELSE 0 END) AS CommunityOwnedPosts,
        SUM(CASE WHEN ps.Status = 'AnswerWithHighScore' THEN 1 ELSE 0 END) AS HighScoreAnswers,
        ROUND(
            (SUM(COALESCE(ps.Score, 0)) * 100.0) / NULLIF(SUM(COALESCE(ps.ViewCount, 0)), 0), 
            2
        ) AS ScorePerView,
        CASE 
            WHEN (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) >= 1000 THEN 'HighlyUpvoted'
            WHEN (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) >= 500 THEN 'ModeratelyUpvoted'
            ELSE 'LowUpvoted'
        END AS ReputationCategory,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(ps.Score, 0)) DESC) AS UserRank,
        NTILE(5) OVER (ORDER BY SUM(COALESCE(ps.Score, 0)) DESC) AS UserScoreQuintile,
        LAG(SUM(COALESCE(ps.Score, 0)), 1) OVER (ORDER BY SUM(COALESCE(ps.Score, 0)) DESC) AS PreviousUserScore,
        (SUM(COALESCE(ps.Score, 0)) - LAG(SUM(COALESCE(ps.Score, 0)), 1) OVER (ORDER BY SUM(COALESCE(ps.Score, 0)) DESC)) AS ScoreDifference,
        COALESCE(
            (SELECT AVG(ps2.Score) 
             FROM Posts ps2 
             WHERE ps2.OwnerUserId = u.Id AND ps2.PostTypeId = 1), 
            0
        ) AS AvgQuestionScore,
        COALESCE(
            (SELECT AVG(ps2.Score) 
             FROM Posts ps2 
             WHERE ps2.OwnerUserId = u.Id AND ps2.PostTypeId = 2), 
            0
        ) AS AvgAnswerScore,
        COALESCE(
            (SELECT COUNT(v.Id) 
             FROM Votes v 
             WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)), 
            0
        ) AS TotalVotesCast
    FROM Users u
    LEFT JOIN PostStats ps ON ps.OwnerUserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
PostsWithComplexCalculations AS (
    SELECT 
        ps.Id AS PostId,
        ps.Title,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.PostCategory,
        ps.ScoreDecile,
        ps.TagCount,
        ps.BodyLengthCategory,
        ps.TotalBounty,
        ps.AverageBounty,
        ps.Status,
        ps.GlobalScoreRank,
        ps.GlobalViewRank,
        ps.PrevScore,
        ps.UserPostRank,
        CASE 
            WHEN ps.PrevScore IS NOT NULL THEN 
                CASE 
                    WHEN ps.Score > ps.PrevScore THEN 'Increased'
                    WHEN ps.Score < ps.PrevScore THEN 'Decreased'
                    ELSE 'Unchanged'
                END
            ELSE 'New'
        END AS ScoreChange,
        CASE 
            WHEN ps.AnswerCount > 0 and ps.AnswerCount >= 3 THEN 'WellAnswered'
            WHEN ps.AnswerCount > 0 and ps.AnswerCount < 3 THEN 'PartiallyAnswered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        CASE 
            WHEN ps.CommentCount > 0 AND ps.CommentCount <= 3 THEN 'FewComments'
            WHEN ps.CommentCount > 3 THEN 'ManyComments'
            ELSE 'NoComments'
        END AS CommentStatus,
        ps.LowerTitle,
        CASE 
            WHEN ps.LowerTitle LIKE '%sql%' OR ps.LowerTitle LIKE '%query%' OR ps.LowerTitle LIKE '%database%' THEN 'Technical'
            WHEN ps.LowerTitle LIKE '%how%' OR ps.LowerTitle LIKE '%what%' OR ps.LowerTitle LIKE '%why%' THEN 'Questionable'
            ELSE 'General'
        END AS QuestionType,
        ps.CleanBody,
        ps.CleanBody = '' AS IsEmptyBody,
        LENGTH(ps.CleanBody) AS BodyLength,
        ps.TagCount > 0 AS HasTags,
        ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AboveAverageScore,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = ps.Id 
                AND ph.PostHistoryTypeId IN (10, 11, 12, 13) 
                AND ph.CreationDate > ps.CreationDate
            ) THEN 'HasHistory'
            ELSE 'NoHistory'
        END AS HasEditHistory
    FROM PostStats ps
),
CorrelatedSubqueryResults AS (
    SELECT 
        ps.Id AS PostId,
        ps.OwnerUserId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.TagCount,
        ps.BodyLengthCategory,
        ps.Status,
        ps.QuestionType,
        ps.ScoreChange,
        ps.AnswerStatus,
        ps.CommentStatus,
        ps.HasEditHistory,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM Posts p 
                WHERE p.ParentId = ps.Id 
                AND p.PostTypeId = 2 
                AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)
            ) THEN 1
            ELSE 0
        END AS HasAboveAvgAnswer,
        CASE 
            WHEN (
                SELECT COUNT(*) 
                FROM Votes v 
                WHERE v.PostId = ps.Id AND v.VoteTypeId IN (2, 3)
            ) > (
                SELECT AVG(v2.Count) 
                FROM (
                    SELECT COUNT(*) AS Count 
                    FROM Votes v3 
                    WHERE v3.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1) 
                    AND v3.VoteTypeId IN (2, 3) 
                    GROUP BY v3.PostId
                ) v2
            ) THEN 1
            ELSE 0
        END AS AboveAvgVotes,
        COALESCE(
            (SELECT COUNT(DISTINCT UserId) 
             FROM Votes v1 
             WHERE v1.PostId = ps.Id 
             AND v1.VoteTypeId = 1
            ), 
            0
        ) AS AcceptanceCount,
        COALESCE(
            (SELECT COUNT(DISTINCT UserId) 
             FROM VoteTypes v2 
             WHERE v2.Id = 1
            ), 
            0
        ) AS IsAcceptedVoteType,
        COALESCE(
            (SELECT MIN(p3.CreationDate) 
             FROM Posts p3 
             WHERE p3.OwnerUserId = ps.OwnerUserId 
             AND p3.PostTypeId = 1
            ), 
            ps.CreationDate
        ) AS FirstQuestionDate,
        COALESCE(
            (SELECT MAX(p4.CreationDate) 
             FROM Posts p4 
             WHERE p4.OwnerUserId = ps.OwnerUserId 
             AND p4.PostTypeId = 2
            ), 
            ps.CreationDate
        ) AS LastAnswerDate,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 
                (
                    SELECT AVG(p5.Score) 
                    FROM Posts p5 
                    WHERE p5.ParentId = ps.Id 
                    AND p5.PostTypeId = 2
                )
            ELSE NULL
        END AS AvgAnswerScore,
        CASE 
            WHEN ps.CommentCount > 0 THEN 
                (
                    SELECT AVG(c1.Score) 
                    FROM Comments c1 
                    WHERE c1.PostId = ps.Id
                )
            ELSE NULL
        END AS AvgCommentScore,
        ps.GlobalScoreRank,
        ps.GlobalViewRank,
        ps.GlobalScoreRank - ps.GlobalViewRank AS ScoreViewRankDifference
    FROM PostsWithComplexCalculations ps
),
FinalPostAnalysis AS (
    SELECT 
        csr.PostId,
        csr.OwnerUserId,
        csr.Title,
        csr.Score,
        csr.ViewCount,
        csr.TagCount,
        csr.BodyLengthCategory,
        csr.Status,
        csr.QuestionType,
        csr.ScoreChange,
        csr.AnswerStatus,
        csr.CommentStatus,
        csr.HasEditHistory,
        csr.HasAboveAvgAnswer,
        csr.AboveAvgVotes,
        csr.AcceptanceCount,
        csr.IsAcceptedVoteType,
        csr.FirstQuestionDate,
        csr.LastAnswerDate,
        csr.AvgAnswerScore,
        csr.AvgCommentScore,
        csr.GlobalScoreRank,
        csr.GlobalViewRank,
        csr.ScoreViewRankDifference,
        CASE 
            WHEN csr.AvgAnswerScore IS NOT NULL AND csr.AvgAnswerScore > 50 THEN 'HighAvgAnswerScore'
            WHEN csr.AvgAnswerScore IS NOT NULL AND csr.AvgAnswerScore > 20 THEN 'MediumAvgAnswerScore'
            ELSE 'LowAvgAnswerScore'
        END AS AnswerScoreCategory,
        CASE 
            WHEN csr.AvgCommentScore IS NOT NULL AND csr.AvgCommentScore > 10 THEN 'HighAvgCommentScore'
            WHEN csr.AvgCommentScore IS NOT NULL AND csr.AvgCommentScore > 5 THEN 'MediumAvgCommentScore'
            ELSE 'LowAvgCommentScore'
        END AS CommentScoreCategory,
        CASE 
            WHEN csr.Score > 100 THEN 'VeryHighScore'
            WHEN csr.Score > 50 THEN 'HighScore'
            WHEN csr.Score > 10 THEN 'MediumScore'
            ELSE 'LowScore'
        END AS ScoreCategory
    FROM CorrelatedSubqueryResults csr
    WHERE csr.OwnerUserId IS NOT NULL
),
UserDetailAnalysis AS (
    SELECT 
        up.UserId,
        up.Reputation,
        up.DisplayName,
        up.Views,
        up.UpVotes,
        up.DownVotes,
        up.TotalPosts,
        up.TotalQuestions,
        up.TotalAnswers,
        up.TotalScore,
        up.AverageScore,
        up.MaxScore,
        up.MinScore,
        up.MedianScore,
        up.AllTitles,
        up.UniqueAnswerCounts,
        up.ClosedPosts,
        up.CommunityOwnedPosts,
        up.HighScoreAnswers,
        up.ScorePerView,
        up.ReputationCategory,
        up.UserRank,
        up.UserScoreQuintile,
        up.ScoreDifference,
        up.AvgQuestionScore,
        up.AvgAnswerScore,
        up.TotalVotesCast,
        CASE 
            WHEN up.TotalAnswers > 0 THEN 
                CAST(up.TotalScore AS FLOAT) / up.TotalAnswers
            ELSE 0
        END AS AvgScorePerAnswer,
        CASE 
            WHEN up.TotalQuestions > 0 THEN 
                CAST(up.TotalScore AS FLOAT) / up.TotalQuestions
            ELSE 0
        END AS AvgScorePerQuestion,
        CASE 
            WHEN up.TotalPosts > 0 THEN 
                ROUND((CAST(up.UpVotes AS FLOAT) / up.TotalPosts) * 100, 2)
            ELSE 0
        END AS UpVotePercentage,
        CASE 
            WHEN up.TotalPosts > 0 THEN 
                ROUND((CAST(up.DownVotes AS FLOAT) / up.TotalPosts) * 100, 2)
            ELSE 0
        END AS DownVotePercentage
    FROM UserPerformance up
),
CombinedAnalysis AS (
    SELECT 
        fpa.PostId,
        fpa.OwnerUserId,
        fpa.Title,
        fpa.Score,
        fpa.ViewCount,
        fpa.TagCount,
        fpa.BodyLengthCategory,
        fpa.Status,
        fpa.QuestionType,
        fpa.ScoreChange,
        fpa.AnswerStatus,
        fpa.CommentStatus,
        fpa.HasEditHistory,
        fpa.HasAboveAvgAnswer,
        fpa.AboveAvgVotes,
        fpa.AcceptanceCount,
        fpa.IsAcceptedVoteType,
        fpa.FirstQuestionDate,
        fpa.LastAnswerDate,
        fpa.AvgAnswerScore,
        fpa.AvgCommentScore,
        fpa.GlobalScoreRank,
        fpa.GlobalViewRank,
        fpa.ScoreViewRankDifference,
        fpa.AnswerScoreCategory,
        fpa.CommentScoreCategory,
        fpa.ScoreCategory,
        uda.Reputation,
        uda.DisplayName,
        uda.Views AS UserViews,
        uda.UpVotes AS UserUpVotes,
        uda.DownVotes AS UserDownVotes,
        uda.TotalPosts AS UserTotalPosts,
        uda.TotalQuestions AS UserTotalQuestions,
        uda.TotalAnswers AS UserTotalAnswers,
        uda.TotalScore AS UserTotalScore,
        uda.AverageScore AS UserAverageScore,
        uda.MaxScore AS UserMaxScore,
        uda.MinScore AS UserMinScore,
        uda.MedianScore AS UserMedianScore,
        uda.AllTitles AS UserAllTitles,
        uda.UniqueAnswerCounts AS UserUniqueAnswerCounts,
        uda.ClosedPosts AS UserClosedPosts,
        uda.CommunityOwnedPosts AS UserCommunityOwnedPosts,
        uda.HighScoreAnswers AS UserHighScoreAnswers,
        uda.ScorePerView AS UserScorePerView,
        uda.ReputationCategory AS UserReputationCategory,
        uda.UserRank,
        uda.UserScoreQuintile,
        uda.ScoreDifference AS UserScoreDifference,
        uda.AvgQuestionScore AS UserAvgQuestionScore,
        uda.AvgAnswerScore AS UserAvgAnswerScore,
        uda.TotalVotesCast AS UserTotalVotesCast,
        uda.AvgScorePerAnswer,
        uda.AvgScorePerQuestion,
        uda.UpVotePercentage,
        uda.DownVotePercentage,
        ROW_NUMBER() OVER (ORDER BY fpa.Score DESC, fpa.ViewCount DESC) AS CombinedRank,
        PERCENT_RANK() OVER (ORDER BY fpa.Score DESC) AS ScorePercentileRank,
        RANK() OVER (ORDER BY uda.TotalScore DESC) AS UserScoreRank,
        CASE 
            WHEN fpa.AvgAnswerScore > 20 THEN 'High'
            WHEN fpa.AvgAnswerScore > 10 THEN 'Medium'
            ELSE 'Low'
        END AS AnswerQuality,
        CASE 
            WHEN fpa.AvgCommentScore > 5 THEN 'High'
            WHEN fpa.AvgCommentScore > 2 THEN 'Medium'
            ELSE 'Low'
        END AS CommentQuality,
        CASE 
            WHEN uda.UserTotalPosts > 50 THEN 'HighActivity'
            WHEN uda.UserTotalPosts > 20 THEN 'ModerateActivity'
            ELSE 'LowActivity'
        END AS UserActivityLevel,
        CASE 
            WHEN fpa.Status = 'Closed' THEN 'ClosedPost'
            WHEN fpa.Status = 'CommunityOwned' THEN 'CommunityOwnedPost'
            ELSE 'RegularPost'
        END AS PostClassification,
        CASE 
            WHEN fpa.HasEditHistory = 'HasHistory' THEN 1
            ELSE 0
        END AS HasEditHistoryFlag,
        CASE 
            WHEN fpa.HasAboveAvgAnswer = 1 THEN 1
            ELSE 0
        END AS HasAboveAvgAnswerFlag,
        CASE 
            WHEN fpa.AboveAvgVotes = 1 THEN 1
            ELSE 0
        END AS AboveAvgVotesFlag
    FROM FinalPostAnalysis fpa
    JOIN UserDetailAnalysis uda ON fpa.OwnerUserId = uda.UserId
)
SELECT 
    *
FROM CombinedAnalysis
WHERE 
    ScoreCategory IN ('HighScore', 'VeryHighScore') 
    AND AnswerStatus IN ('WellAnswered', 'PartiallyAnswered')
    AND CommentStatus IN ('FewComments', 'ManyComments')
    AND PostClassification IN ('RegularPost', 'ClosedPost')
    AND UserActivityLevel IN ('HighActivity', 'ModerateActivity')
    AND ScorePercentileRank > 0.9
    AND (Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1))
    AND (UserTotalScore > (SELECT AVG(TotalScore) FROM UserDetailAnalysis))
    AND (UserTotalPosts > 0)
    AND (UserTotalAnswers > 0)
    AND (UserTotalQuestions > 0)
    AND UserReputationCategory IN ('HighlyUpvoted', 'ModeratelyUpvoted')
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = CombinedAnalysis.OwnerUserId 
        AND p.PostTypeId = 1 
        AND p.Score > 100
    )
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = CombinedAnalysis.OwnerUserId 
        AND p.PostTypeId = 2 
        AND p.Score > 50
    )
    AND (
        CASE 
            WHEN UserTotalAnswers = 0 THEN 0
            ELSE (AvgScorePerAnswer / (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2))
        END
    ) > 1
    AND (
        CASE 
            WHEN UserTotalQuestions = 0 THEN 0
            ELSE (AvgScorePerQuestion / (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1))
        END
    ) > 1
    AND NOT EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = CombinedAnalysis.OwnerUserId 
        AND p.PostTypeId = 2 
        AND p.Score < 0
    )
ORDER BY 
    Score DESC, 
    ViewCount DESC, 
    UserTotalScore DESC
LIMIT 1000;