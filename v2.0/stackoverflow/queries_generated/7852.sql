-- {"query": "7852.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2724} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
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
        p.Body,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentPostByType,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS MovingAvgScore,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above Average'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below Average'
            ELSE 'Average'
        END AS ScoreCategory,
        COALESCE(p.Title, '') + ' | ' + COALESCE(p.Tags, '') AS TitleTagConcat,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' 
            THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
            ELSE ARRAY[]::VARCHAR[]
        END AS TagArray,
        COALESCE(DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP), 0) AS DaysSinceCreation,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Question without Accepted Answer'
            ELSE 'Other'
        END AS PostTypeStatus,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS UpDownVoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS FavoriteCountOnPost,
        (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS FirstBountyDate,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS LastBountyCloseDate,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenDeleteCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers only
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
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        AVG(COALESCE(p.Score, 0)) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) AS AccountAgeDays,
        CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
        CASE WHEN u.Location IS NULL OR u.Location = '' THEN 'No Location' ELSE 'Has Location' END AS LocationStatus,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newcomer'
        END AS ReputationTier,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.WebsiteUrl, u.Location, u.CreationDate
),
PostTagAnalysis AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.ScoreRank,
        ps.Score,
        ps.ViewCount,
        ps.CommentCount,
        ps.AnswerCount,
        ps.CreationDate,
        ps.TitleTagConcat,
        ps.TagArray,
        CASE WHEN ARRAY_LENGTH(ps.TagArray, 1) IS NULL THEN 0 ELSE ARRAY_LENGTH(ps.TagArray, 1) END AS TagCount,
        COALESCE(ps.TagArray[1], '') AS PrimaryTag,
        CASE WHEN ps.TagArray[1] LIKE '%java%' THEN 'Java Related' 
             WHEN ps.TagArray[1] LIKE '%python%' THEN 'Python Related'
             WHEN ps.TagArray[1] LIKE '%javascript%' THEN 'JavaScript Related' 
             ELSE 'Other'
        END AS PrimaryTagCategory,
        COALESCE(ps.OwnerUserId, 0) AS OwnerUserId,
        'Post_' || ps.PostId AS PostTagIdentifier,
        CASE WHEN ps.AnswerCount > 0 AND ps.Score < 0 THEN 'Question with Negative Score and Answers'
             WHEN ps.AnswerCount = 0 AND ps.Score < 0 THEN 'Question with Negative Score and No Answers'
             ELSE 'Other'
        END AS QuestionEvaluation
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
TopActivityUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.TotalViews,
        ua.AverageScore,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.ReputationTier,
        ua.AccountAgeDays,
        RANK() OVER (ORDER BY ua.TotalViews DESC) AS ViewRank,
        RANK() OVER (ORDER BY ua.TotalScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
        CASE 
            WHEN ua.ReputationTier IN ('Expert', 'Intermediate') AND ua.TotalPosts > 100 THEN 'Active Power User'
            WHEN ua.ReputationTier = 'Beginner' AND ua.TotalPosts > 50 THEN 'Active Beginner'
            WHEN ua.ReputationTier = 'Newcomer' AND ua.TotalPosts > 10 THEN 'Active Newcomer'
            ELSE 'Regular User'
        END AS UserActivityLevel
    FROM UserActivity ua
    WHERE ua.TotalPosts > 0
),
ComplexTagAnalysis AS (
    SELECT 
        pta.PostId,
        pta.Title,
        pta.Tags,
        pta.ScoreRank,
        pta.Score,
        pta.ViewCount,
        pta.CommentCount,
        pta.AnswerCount,
        pta.CreationDate,
        pta.PrimaryTag,
        pta.PrimaryTagCategory,
        pta.QuestionEvaluation,
        pta.PostTagIdentifier,
        ROW_NUMBER() OVER (ORDER BY pta.TagCount DESC) AS TagCountRank,
        CASE 
            WHEN pta.TagCount > 5 THEN 'Highly Tagged'
            WHEN pta.TagCount BETWEEN 3 AND 5 THEN 'Moderately Tagged'
            WHEN pta.TagCount < 3 THEN 'Lightly Tagged'
            ELSE 'No Tags'
        END AS TaggingCategory,
        DENSE_RANK() OVER (PARTITION BY pta.PrimaryTagCategory ORDER BY pta.Score DESC) AS ScoreRankPerCategory,
        AVG(pta.Score) OVER (PARTITION BY pta.PrimaryTagCategory) AS AvgScorePerCategory,
        CASE 
            WHEN pta.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Category Average'
            WHEN pta.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Category Average'
            ELSE 'Category Average'
        END AS RelativeScoreToCategory,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Tags LIKE '%' || pta.PrimaryTag || '%') AS CountOfPostsWithThisTag,
        CASE 
            WHEN pta.Score > 0 AND pta.AnswerCount > 0 THEN 'Active Engagement'
            WHEN pta.Score > 0 AND pta.AnswerCount = 0 THEN 'Scored but No Answers'
            WHEN pta.Score <= 0 THEN 'No Engagement'
            ELSE 'Undefined'
        END AS EngagementStatus
    FROM PostTagAnalysis pta
    WHERE pta.TagCount > 0
),
UserPostPerformance AS (
    SELECT 
        ta.PostId,
        ta.Title,
        ta.Score,
        ta.ViewCount,
        ta.CommentCount,
        ta.AnswerCount,
        ta.ScoreRank,
        ta.PostTypeStatus,
        ta.ScoreCategory,
        ta.DaysSinceCreation,
        ta.CloseReopenDeleteCount,
        ta.FirstBountyDate,
        ta.LastBountyCloseDate,
        ta.UpDownVoteCount,
        ta.CommentCountOnPost,
        ta.FavoriteCountOnPost,
        CASE 
            WHEN ta.CloseReopenDeleteCount > 0 THEN 'Has Activity History'
            WHEN ta.FirstBountyDate IS NOT NULL THEN 'Has Bounty History'
            WHEN ta.UpDownVoteCount > 0 THEN 'Has Voting History'
            ELSE 'No Significant History'
        END AS PostActivityHistory,
        'Post-' || ta.PostId || '-User-' || COALESCE(ta.OwnerUserId, 0) AS PostUserIdentifier,
        CASE 
            WHEN ta.ViewCount > 1000 AND ta.Score > 50 THEN 'High Impact'
            WHEN ta.ViewCount > 500 AND ta.Score > 25 THEN 'Medium Impact'
            WHEN ta.ViewCount > 100 AND ta.Score > 10 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END AS ImpactLevel,
        CASE 
            WHEN ta.ViewCount > 0 THEN CAST(ta.Score AS FLOAT) / CAST(ta.ViewCount AS FLOAT) 
            ELSE 0.0
        END AS ScorePerViewRatio
    FROM PostStats ta
)
SELECT 
    uap.PostId,
    uap.Title,
    uap.Score,
    uap.ViewCount,
    uap.CommentCount,
    uap.AnswerCount,
    uap.ScoreRank,
    uap.PostTypeStatus,
    uap.ScoreCategory,
    uap.DaysSinceCreation,
    uap.CloseReopenDeleteCount,
    uap.FirstBountyDate,
    uap.LastBountyCloseDate,
    uap.UpDownVoteCount,
    uap.CommentCountOnPost,
    uap.FavoriteCountOnPost,
    uap.PostActivityHistory,
    uap.PostUserIdentifier,
    uap.ImpactLevel,
    uap.ScorePerViewRatio,
    ca.TagCountRank,
    ca.TaggingCategory,
    ca.ScoreRankPerCategory,
    ca.AvgScorePerCategory,
    ca.RelativeScoreToCategory,
    ca.CountOfPostsWithThisTag,
    ca.EngagementStatus,
    CASE 
        WHEN uap.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1 
        WHEN uap.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN -1 
        ELSE 0 
    END AS ScoreDeviationFromAverage,
    'ComplexAnalysisResult' AS AnalysisType
FROM UserPostPerformance uap
INNER JOIN ComplexTagAnalysis ca ON uap.PostId = ca.PostId
WHERE (uap.ViewCount > 100 OR uap.Score > 10) 
    AND uap.OwnerUserId IS NOT NULL
    AND uap.DaysSinceCreation <= 365
    AND ca.TagCount >= 2
ORDER BY uap.Score DESC, uap.ViewCount DESC
LIMIT 500 OFFSET 50;