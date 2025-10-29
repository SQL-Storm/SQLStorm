-- {"query": "7932.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3059} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        DATEDIFF(day, LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), p.CreationDate) AS DaysSinceLastPost,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsPerUser,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
            ELSE 'Average'
        END AS ScoreCategory,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) AS CleanTags,
        STRING_AGG(
            CASE WHEN p.Tags IS NOT NULL THEN TRIM(BOTH '<>' FROM SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2)) END, 
            ','
        ) OVER (PARTITION BY p.OwnerUserId) AS UserTagList
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.PostId) AS TotalPosts,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastActivity,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.PostId END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.PostId END) AS AnswersCount,
        COUNT(DISTINCT CASE WHEN ps.PostRank = 1 THEN ps.PostId END) AS LatestPostCount,
        STRING_AGG(DISTINCT ps.PostType, ',') AS UserPostTypes,
        COUNT(DISTINCT ps.UserTagList) AS UniqueTagLists
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
ComplexPostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.HasAcceptedAnswer,
        ps.EngagementScore,
        ps.PostRank,
        ps.DaysSinceLastPost,
        ps.AvgScorePerUser,
        ps.TotalPostsPerUser,
        ps.ScoreCategory,
        ps.CleanTags,
        ps.UserTagList,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ps.PostId AND p2.PostTypeId = 2 AND p2.DeletionDate IS NULL),
            0
        ) AS AnswerCountWithDeletions,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.PostId),
            0
        ) AS CommentCountIncludingDeleted,
        CASE 
            WHEN ps.PostRank = 1 AND ps.DaysSinceLastPost > 30 THEN 'Inactive for over 30 days'
            WHEN ps.PostRank = 1 AND ps.DaysSinceLastPost <= 30 THEN 'Recently active'
            WHEN ps.PostRank = 1 THEN 'New user activity'
            ELSE 'Regular activity'
        END AS ActivityStatus,
        CASE 
            WHEN ps.Score >= 100 AND ps.PostType = 'Question' THEN 'Highly Rated Question'
            WHEN ps.Score >= 50 AND ps.PostType = 'Answer' THEN 'Highly Rated Answer'
            WHEN ps.Score < 0 THEN 'Downvoted Content'
            ELSE 'Regular Content'
        END AS ContentRating,
        LTRIM(RTRIM(SUBSTRING(ps.Body, 1, 100))) AS BodyPreview,
        CASE 
            WHEN ps.Tags LIKE '%<c++>%' THEN 'C++ Related'
            WHEN ps.Tags LIKE '%<python>%' THEN 'Python Related'
            WHEN ps.Tags LIKE '%<javascript>%' THEN 'JavaScript Related'
            ELSE 'Other Topic'
        END AS TopicCategory,
        DATEDIFF(day, ps.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        (ps.ViewCount * 0.1 + ps.AnswerCount * 2 + ps.CommentCount * 0.5 + ps.Score * 0.8 + ps.FavoriteCount * 1.5) AS WeightedEngagementScore
    FROM PostStats ps
),
FinalAnalysis AS (
    SELECT 
        cpa.PostId,
        cpa.OwnerUserId,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount AS ReportedAnswerCount,
        cpa.AnswerCountWithDeletions,
        cpa.CommentCount AS ReportedCommentCount,
        cpa.CommentCountIncludingDeleted,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.LastActivityDate,
        cpa.Title,
        cpa.Tags,
        cpa.PostType,
        cpa.HasAcceptedAnswer,
        cpa.EngagementScore,
        cpa.PostRank,
        cpa.DaysSinceLastPost,
        cpa.AvgScorePerUser,
        cpa.TotalPostsPerUser,
        cpa.ScoreCategory,
        cpa.CleanTags,
        cpa.UserTagList,
        cpa.ActivityStatus,
        cpa.ContentRating,
        cpa.BodyPreview,
        cpa.TopicCategory,
        cpa.AgeInDays,
        cpa.WeightedEngagementScore,
        ROW_NUMBER() OVER (PARTITION BY cpa.ContentRating ORDER BY cpa.WeightedEngagementScore DESC) AS RankByContentRating,
        RANK() OVER (ORDER BY cpa.WeightedEngagementScore DESC) AS RankByEngagement,
        DENSE_RANK() OVER (ORDER BY cpa.AgeInDays ASC) AS RankByAge,
        PERCENT_RANK() OVER (ORDER BY cpa.WeightedEngagementScore) AS PercentileEngagement,
        NTILE(4) OVER (ORDER BY cpa.WeightedEngagementScore) AS QuartileEngagement,
        LAG(cpa.PostId) OVER (ORDER BY cpa.WeightedEngagementScore DESC) AS PreviousPostId,
        LEAD(cpa.PostId) OVER (ORDER BY cpa.WeightedEngagementScore DESC) AS NextPostId,
        CASE 
            WHEN (cpa.DaysSinceLastPost IS NOT NULL AND cpa.DaysSinceLastPost > 30) OR cpa.AgeInDays > 30 THEN 1
            ELSE 0
        END AS IsOldContent,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cpa.PostId AND v.VoteTypeId = 2),
            0
        ) AS UpVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cpa.PostId AND v.VoteTypeId = 3),
            0
        ) AS DownVotes,
        CASE 
            WHEN cpa.WeightedEngagementScore > (SELECT AVG(WeightedEngagementScore) FROM ComplexPostAnalysis) THEN 'Above Average'
            ELSE 'Below Average'
        END AS EngagementLevel,
        CASE 
            WHEN cpa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 2 THEN 'Exceptional'
            WHEN cpa.Score BETWEEN (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AND (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 2 THEN 'Good'
            ELSE 'Average Or Below'
        END AS QualityAssessment
    FROM ComplexPostAnalysis cpa
),
UserDetailedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.AccountId,
        uas.TotalPosts,
        uas.TotalScore,
        uas.AvgScore,
        uas.LastActivity,
        uas.QuestionsCount,
        uas.AnswersCount,
        uas.LatestPostCount,
        uas.UserPostTypes,
        uas.UniqueTagLists,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.AcceptedAnswerId IS NOT NULL),
            0
        ) AS AcceptedAnswers,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 1),
            0
        ) AS AcceptedVotes,
        CASE 
            WHEN uas.Reputation > 1000 THEN 'High Reputation'
            WHEN uas.Reputation > 500 THEN 'Medium Reputation'
            ELSE 'Low Reputation'
        END AS ReputationTier
    FROM UserActivityStats uas
)
SELECT 
    fa.PostId,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.ReportedAnswerCount,
    fa.AnswerCountWithDeletions,
    fa.ReportedCommentCount,
    fa.CommentCountIncludingDeleted,
    fa.FavoriteCount,
    fa.CreationDate,
    fa.LastActivityDate,
    fa.Title,
    fa.Tags,
    fa.PostType,
    fa.HasAcceptedAnswer,
    fa.EngagementScore,
    fa.PostRank,
    fa.DaysSinceLastPost,
    fa.AvgScorePerUser,
    fa.TotalPostsPerUser,
    fa.ScoreCategory,
    fa.CleanTags,
    fa.UserTagList,
    fa.ActivityStatus,
    fa.ContentRating,
    fa.BodyPreview,
    fa.TopicCategory,
    fa.AgeInDays,
    fa.WeightedEngagementScore,
    fa.RankByContentRating,
    fa.RankByEngagement,
    fa.RankByAge,
    fa.PercentileEngagement,
    fa.QuartileEngagement,
    fa.IsOldContent,
    fa.UpVotes,
    fa.DownVotes,
    fa.EngagementLevel,
    fa.QualityAssessment,
    uda.DisplayName,
    uda.Reputation,
    uda.Views AS UserViews,
    uda.UpVotes AS UserUpVotes,
    uda.DownVotes AS UserDownVotes,
    uda.TotalPosts AS UserTotalPosts,
    uda.TotalScore AS UserTotalScore,
    uda.AvgScore AS UserAvgScore,
    uda.QuestionsCount AS UserQuestionsCount,
    uda.AnswersCount AS UserAnswersCount,
    uda.ReputationTier,
    CASE 
        WHEN fa.WeightedEngagementScore >= 100 AND fa.IsOldContent = 0 THEN 'High Value Current'
        WHEN fa.WeightedEngagementScore >= 100 AND fa.IsOldContent = 1 THEN 'High Value Legacy'
        WHEN fa.WeightedEngagementScore < 100 AND fa.IsOldContent = 0 THEN 'Low Value Current'
        ELSE 'Low Value Legacy'
    END AS ContentValueCategory,
    DATEDIFF(day, CAST('2010-01-01' AS DATE), fa.CreationDate) AS DaysFromStartDate,
    CASE 
        WHEN fa.Score > 200 THEN 'Very High'
        WHEN fa.Score > 100 THEN 'High'
        WHEN fa.Score > 50 THEN 'Medium'
        WHEN fa.Score > 10 THEN 'Low'
        ELSE 'Very Low'
    END AS ScoreRange,
    CASE 
        WHEN fa.Tags IS NULL THEN 'No Tags'
        WHEN LENGTH(fa.Tags) < 10 THEN 'Minimal Tags'
        WHEN LENGTH(fa.Tags) BETWEEN 10 AND 50 THEN 'Standard Tags'
        ELSE 'Extensive Tags'
    END AS TagDensity,
    CASE 
        WHEN fa.BodyPreview LIKE '%<code>%' THEN 'Code Present'
        ELSE 'No Code'
    END AS CodePresence,
    COALESCE(
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = fa.PostId AND pl.LinkTypeId = 1),
        0
    ) AS ExternalLinks,
    ROW_NUMBER() OVER (ORDER BY fa.WeightedEngagementScore DESC, fa.CreationDate ASC) AS OverallRank,
    CASE 
        WHEN fa.PostId IN (
            SELECT PostId 
            FROM (SELECT PostId, COUNT(*) as links FROM PostLinks GROUP BY PostId) pl 
            WHERE links > 5
        ) THEN 1
        ELSE 0
    END AS HighlyLinkedPost
FROM FinalAnalysis fa
LEFT JOIN UserDetailedAnalysis uda ON fa.OwnerUserId = uda.UserId
WHERE fa.WeightedEngagementScore BETWEEN 0 AND 1000000
  AND (fa.PostType = 'Question' OR fa.PostType = 'Answer')
  AND fa.AgeInDays > 0
  AND (uda.ReputationTier = 'High Reputation' OR uda.ReputationTier = 'Medium Reputation')
  AND fa.ContentRating NOT IN ('Downvoted Content')
  AND NOT (fa.TopicCategory = 'Other Topic' AND (fa.Score < 10 OR fa.ViewCount < 100))
ORDER BY fa.WeightedEngagementScore DESC, fa.CreationDate ASC
LIMIT 1000;