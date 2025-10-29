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
        p.Body,
        p.LastActivityDate,
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.AnswerCount, 0) AS AnswerCountCoalesced,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 100 THEN 'HighlyVotedQuestion'
            WHEN p.PostTypeId = 1 AND p.Score BETWEEN 10 AND 100 THEN 'ModeratelyVotedQuestion'
            WHEN p.PostTypeId = 1 AND p.Score < 10 THEN 'LowVotedQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 50 THEN 'HighlyVotedAnswer'
            WHEN p.PostTypeId = 2 AND p.Score BETWEEN 5 AND 50 THEN 'ModeratelyVotedAnswer'
            WHEN p.PostTypeId = 2 AND p.Score < 5 THEN 'LowVotedAnswer'
            ELSE 'Other'
        END AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(10) OVER (ORDER BY p.CreationDate) AS CreationDateQuartile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        MAX(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS MaxUserViews,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 
                (
                    SELECT COUNT(*) FROM (
                        SELECT TRIM(x) AS tag
                        FROM (
                            SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM p.Tags), '><') AS x
                        ) AS t
                    ) sub WHERE sub.tag IS NOT NULL AND sub.tag <> ''
                )
            ELSE 0 
        END AS TagCount,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL THEN 
                (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3))
            ELSE 0 
        END AS VoteCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
                (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
            ELSE 0 
        END AS AcceptedAnswerScore
    FROM Posts p
    WHERE p.CreationDate >= DATE '2019-01-01'
),
PostWithUserDetails AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.LastActivityDate,
        ps.ParentId,
        ps.AcceptedAnswerId,
        ps.AnswerCountCoalesced,
        ps.PostCategory,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.CreationDateQuartile,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.MaxUserViews,
        ps.TotalUserPosts,
        ps.TagCount,
        ps.VoteCount,
        ps.AcceptedAnswerScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(u.Views, 0) + COALESCE(ps.ViewCount, 0) AS TotalViews,
        ps.Score - COALESCE(ps.PreviousScore, 0) AS ScoreChange,
        CASE 
            WHEN ps.Score > 100 THEN 'Elite'
            WHEN ps.Score BETWEEN 10 AND 100 THEN 'Regular'
            ELSE 'Casual'
        END AS UserActivityLevel,
        CASE 
            WHEN ps.AnswerCountCoalesced > 5 THEN 'ActiveAnswerer'
            WHEN ps.AnswerCountCoalesced > 0 THEN 'OccasionalAnswerer'
            ELSE 'NoAnswers'
        END AS AnsweringActivity,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags <> '' THEN 
                (CASE WHEN ps.TagCount > 3 THEN 'TagRich' WHEN ps.TagCount > 1 THEN 'TagModerate' ELSE 'TagSparse' END)
            ELSE 'NoTags'
        END AS TagComplexity
    FROM PostStats ps
    LEFT JOIN Users u ON ps.OwnerUserId = u.Id
    WHERE ps.PostTypeId IN (1, 2)
),
AnswerStats AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.LastActivityDate,
        ps.ParentId,
        ps.AcceptedAnswerId,
        ps.AnswerCountCoalesced,
        ps.PostCategory,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.CreationDateQuartile,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.MaxUserViews,
        ps.TotalUserPosts,
        ps.TagCount,
        ps.VoteCount,
        ps.AcceptedAnswerScore,
        ps.OwnerDisplayName,
        ps.Reputation,
        ps.UserViews,
        ps.UpVotes,
        ps.DownVotes,
        ps.AccountId,
        ps.TotalViews,
        ps.ScoreChange,
        ps.UserActivityLevel,
        ps.AnsweringActivity,
        ps.TagComplexity,
        CASE 
            WHEN ps.PostTypeId = 2 THEN 
                COALESCE((SELECT AVG(s.Score) FROM Posts s WHERE s.ParentId = ps.Id AND s.PostTypeId = 2), 0)
            ELSE 0 
        END AS AvgAnswerScore,
        CASE 
            WHEN ps.PostTypeId = 2 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = ps.Id AND PostTypeId = 2)
            ELSE 0 
        END AS AnswerCountIncludingDeleted,
        CASE
            WHEN ps.PostTypeId = 1 AND ps.AcceptedAnswerId IS NOT NULL 
            THEN (SELECT Score FROM Posts WHERE Id = ps.AcceptedAnswerId AND PostTypeId = 2)
            ELSE 0 
        END AS FinalAcceptedAnswerScore
    FROM PostWithUserDetails ps
    WHERE ps.PostTypeId IN (1, 2)
),
QuestionTags AS (
    SELECT 
        as1.Id,
        as1.PostTypeId,
        as1.Score,
        as1.ViewCount,
        as1.AnswerCount,
        as1.CommentCount,
        as1.FavoriteCount,
        as1.CreationDate,
        as1.OwnerUserId,
        as1.Title,
        as1.Tags,
        as1.Body,
        as1.LastActivityDate,
        as1.ParentId,
        as1.AcceptedAnswerId,
        as1.AnswerCountCoalesced,
        as1.PostCategory,
        as1.UserPostRank,
        as1.ScoreRank,
        as1.CreationDateQuartile,
        as1.PreviousScore,
        as1.NextScore,
        as1.AvgUserScore,
        as1.MaxUserViews,
        as1.TotalUserPosts,
        as1.TagCount,
        as1.VoteCount,
        as1.AcceptedAnswerScore,
        as1.OwnerDisplayName,
        as1.Reputation,
        as1.UserViews,
        as1.UpVotes,
        as1.DownVotes,
        as1.AccountId,
        as1.TotalViews,
        as1.ScoreChange,
        as1.UserActivityLevel,
        as1.AnsweringActivity,
        as1.TagComplexity,
        as1.AvgAnswerScore,
        as1.AnswerCountIncludingDeleted,
        as1.FinalAcceptedAnswerScore,
        CASE 
            WHEN as1.Tags IS NOT NULL AND as1.Tags <> '' THEN 
                (
                    SELECT string_agg(tag, ', ') FROM (
                        SELECT TRIM(x) AS tag
                        FROM (
                            SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM as1.Tags), '><') AS x
                        ) AS t
                    ) sub WHERE sub.tag IS NOT NULL AND sub.tag <> ''
                )
            ELSE 'No Tags' 
        END AS TagList,
        CASE 
            WHEN as1.Tags IS NOT NULL AND as1.Tags <> '' THEN 
                (
                    SELECT COUNT(*) FROM (
                        SELECT TRIM(x) AS tag
                        FROM (
                            SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM as1.Tags), '><') AS x
                        ) AS t
                    ) sub WHERE sub.tag IS NOT NULL AND sub.tag <> ''
                )
            ELSE 0 
        END AS TagCountFinal
    FROM AnswerStats as1
),
UserPostSummary AS (
    SELECT 
        qt.Id,
        qt.PostTypeId,
        qt.Score,
        qt.ViewCount,
        qt.AnswerCount,
        qt.CommentCount,
        qt.FavoriteCount,
        qt.CreationDate,
        qt.OwnerUserId,
        qt.Title,
        qt.Tags,
        qt.Body,
        qt.LastActivityDate,
        qt.ParentId,
        qt.AcceptedAnswerId,
        qt.AnswerCountCoalesced,
        qt.PostCategory,
        qt.UserPostRank,
        qt.ScoreRank,
        qt.CreationDateQuartile,
        qt.PreviousScore,
        qt.NextScore,
        qt.AvgUserScore,
        qt.MaxUserViews,
        qt.TotalUserPosts,
        qt.TagCount,
        qt.VoteCount,
        qt.AcceptedAnswerScore,
        qt.OwnerDisplayName,
        qt.Reputation,
        qt.UserViews,
        qt.UpVotes,
        qt.DownVotes,
        qt.AccountId,
        qt.TotalViews,
        qt.ScoreChange,
        qt.UserActivityLevel,
        qt.AnsweringActivity,
        qt.TagComplexity,
        qt.AvgAnswerScore,
        qt.AnswerCountIncludingDeleted,
        qt.FinalAcceptedAnswerScore,
        qt.TagList,
        qt.TagCountFinal,
        ROW_NUMBER() OVER (ORDER BY qt.TotalViews DESC) AS OverallViewRank,
        RANK() OVER (ORDER BY qt.Reputation DESC) AS UserReputationRank,
        DENSE_RANK() OVER (ORDER BY qt.Score DESC) AS UserScoreRank,
        SUM(qt.ViewCount) OVER (PARTITION BY qt.OwnerUserId) AS TotalUserViews,
        AVG(qt.ViewCount) OVER (PARTITION BY qt.OwnerUserId) AS AvgUserPostViews,
        MAX(qt.Score) OVER (PARTITION BY qt.OwnerUserId) AS MaxUserPostScore,
        CASE 
            WHEN qt.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE OwnerUserId = qt.OwnerUserId) THEN 'AboveUserAverage'
            ELSE 'BelowUserAverage'
        END AS ViewPerformance,
        CASE 
            WHEN qt.Score > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = qt.OwnerUserId) THEN 'AboveUserAverageScore'
            ELSE 'BelowUserAverageScore'
        END AS ScorePerformance,
        CASE 
            WHEN qt.UserViews > (SELECT AVG(Views) FROM Users) THEN 'AboveGlobalAverage'
            ELSE 'BelowGlobalAverage'
        END AS GlobalViewPerformance,
        CASE 
            WHEN qt.Reputation >= 10000 THEN 'EliteUser'
            WHEN qt.Reputation >= 1000 THEN 'ModerateUser'
            WHEN qt.Reputation >= 100 THEN 'BeginnerUser'
            ELSE 'NewUser'
        END AS UserProfileLevel
    FROM QuestionTags qt
),
ComplexPostAnalysis AS (
    SELECT 
        ups.Id,
        ups.PostTypeId,
        ups.Score,
        ups.ViewCount,
        ups.AnswerCount,
        ups.CommentCount,
        ups.FavoriteCount,
        ups.CreationDate,
        ups.OwnerUserId,
        ups.Title,
        ups.Tags,
        ups.Body,
        ups.LastActivityDate,
        ups.ParentId,
        ups.AcceptedAnswerId,
        ups.AnswerCountCoalesced,
        ups.PostCategory,
        ups.UserPostRank,
        ups.ScoreRank,
        ups.CreationDateQuartile,
        ups.PreviousScore,
        ups.NextScore,
        ups.AvgUserScore,
        ups.MaxUserViews,
        ups.TotalUserPosts,
        ups.TagCount,
        ups.VoteCount,
        ups.AcceptedAnswerScore,
        ups.OwnerDisplayName,
        ups.Reputation,
        ups.UserViews,
        ups.UpVotes,
        ups.DownVotes,
        ups.AccountId,
        ups.TotalViews,
        ups.ScoreChange,
        ups.UserActivityLevel,
        ups.AnsweringActivity,
        ups.TagComplexity,
        ups.AvgAnswerScore,
        ups.AnswerCountIncludingDeleted,
        ups.FinalAcceptedAnswerScore,
        ups.TagList,
        ups.TagCountFinal,
        ups.OverallViewRank,
        ups.UserReputationRank,
        ups.UserScoreRank,
        ups.TotalUserViews,
        ups.AvgUserPostViews,
        ups.MaxUserPostScore,
        ups.ViewPerformance,
        ups.ScorePerformance,
        ups.GlobalViewPerformance,
        ups.UserProfileLevel,
        (ups.Score * ups.AnswerCountCoalesced) AS ScoreAnswerProduct,
        (ups.ViewCount * ups.FavoriteCount) AS ViewFavoriteProduct,
        (ups.TagCountFinal * ups.Score) AS TagScoreRatio,
        CASE 
            WHEN ups.Score > 0 AND ups.AnswerCountCoalesced > 0 THEN
                CASE 
                    WHEN (CAST(ups.Score AS numeric) / NULLIF(ups.AnswerCountCoalesced,0)) > 5 THEN 'HighValue'
                    WHEN (CAST(ups.Score AS numeric) / NULLIF(ups.AnswerCountCoalesced,0)) BETWEEN 1 AND 5 THEN 'MediumValue'
                    ELSE 'LowValue'
                END
            ELSE 'NoAnswerValue'
        END AS ValuePerAnswer,
        CASE 
            WHEN ups.PostCategory IN ('HighlyVotedQuestion', 'HighlyVotedAnswer') THEN 
                (CASE 
                    WHEN ups.UserViews > 1000 THEN 'Viral'
                    WHEN ups.UserViews > 100 THEN 'Popular'
                    ELSE 'Moderate'
                END)
            ELSE 'Normal'
        END AS PopularityLevel,
        RANK() OVER (ORDER BY ups.Score DESC) - ROW_NUMBER() OVER (ORDER BY ups.Score DESC) AS ScoreRankDeviation,
        CASE 
            WHEN ups.PostTypeId = 1 AND ups.AnswerCountCoalesced = 0 THEN 'UnansweredQuestion'
            WHEN ups.PostTypeId = 1 AND ups.AcceptedAnswerId IS NOT NULL THEN 'AnsweredWithAccept'
            WHEN ups.PostTypeId = 1 AND ups.AcceptedAnswerId IS NULL AND ups.AnswerCountCoalesced > 0 THEN 'AnsweredWithoutAccept'
            ELSE 'OtherQuestion'
        END AS QuestionStatus,
        CASE 
            WHEN ups.OwnerUserId IS NOT NULL AND ups.OwnerUserId IN (
                SELECT UserId FROM Badges WHERE Name IN ('Yearling', 'Altruist', 'Great Answer', 'Good Answer')
            ) THEN 'ValuedContributor'
            ELSE 'StandardUser'
        END AS ContributorType,
        COALESCE(
            (SELECT 1 FROM Votes v WHERE v.PostId = ups.Id AND v.VoteTypeId = 2 AND v.UserId = ups.OwnerUserId LIMIT 1),
            0
        ) AS UserUpvotedOwnPost,
        CASE 
            WHEN ups.Title IS NOT NULL THEN 
                TRIM(UPPER(SUBSTR(ups.Title, 1, 100)) || '...' || SUBSTR(ups.Title, GREATEST(LENGTH(ups.Title)-49,1), 50))
            ELSE 'No Title Available'
        END AS ProcessedTitle,
        CASE 
            WHEN ups.Tags IS NULL OR ups.Tags = '' THEN 'No Tags Provided'
            ELSE 'Tags Present'
        END AS TagAvailability,
        ROUND(
            CASE WHEN ups.Score > 0 THEN LN(CAST(ups.Score AS numeric)) ELSE 0 END, 
            2
        ) AS LogScore,
        LAG(ups.Score, 1, 0) OVER (
            PARTITION BY ups.OwnerUserId 
            ORDER BY ups.CreationDate ASC
        ) AS PreviousPostScore,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ups.Id 
             AND c.CreationDate >= ups.CreationDate - INTERVAL '7 days'
            ), 0
        ) AS RecentCommentsCount
    FROM UserPostSummary ups
)
SELECT 
    COUNT(*) AS TotalPosts,
    COUNT(CASE WHEN cpa.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN cpa.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    AVG(cpa.Score) AS AvgScore,
    AVG(cpa.ViewCount) AS AvgViews,
    SUM(cpa.ViewCount) AS TotalViews,
    AVG(cpa.Reputation) AS AvgReputation,
    MAX(cpa.Score) AS MaxScore,
    MAX(cpa.ViewCount) AS MaxViews,
    string_agg(DISTINCT cpa.QuestionStatus, ', ') AS QuestionStatuses,
    string_agg(DISTINCT cpa.PopularityLevel, ', ') AS PopularityLevels,
    COUNT(DISTINCT cpa.OwnerUserId) AS UniqueUsers,
    string_agg(DISTINCT cpa.TagComplexity, ', ') AS TagComplexities,
    string_agg(DISTINCT cpa.ValuePerAnswer, ', ') AS ValuePerAnswers,
    string_agg(DISTINCT cpa.GlobalViewPerformance, ', ') AS GlobalViewPerformances,
    string_agg(DISTINCT cpa.UserProfileLevel, ', ') AS UserProfileLevels,
    string_agg(DISTINCT cpa.ContributorType, ', ') AS ContributorTypes,
    COUNT(CASE WHEN cpa.UserUpvotedOwnPost = 1 THEN 1 END) AS SelfUpvotedPosts,
    COUNT(CASE WHEN cpa.ProcessedTitle <> 'No Title Available' THEN 1 END) AS PostsWithTitle,
    COUNT(CASE WHEN cpa.TagAvailability = 'Tags Present' THEN 1 END) AS PostsWithTags,
    COUNT(CASE WHEN cpa.LogScore > 0 THEN 1 END) AS PostsWithLogScore,
    COUNT(CASE WHEN cpa.RecentCommentsCount > 0 THEN 1 END) AS PostsWithRecentComments,
    AVG(CASE WHEN cpa.Score > 0 THEN cpa.Score ELSE NULL END) AS AvgPositiveScore,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            (COUNT(CASE WHEN cpa.ViewCount > 0 THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END AS PostsWithViewsPercentage,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            (COUNT(CASE WHEN cpa.Score > 10 THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END AS HighlyRatedPostsPercentage,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            (COUNT(CASE WHEN cpa.Score > 100 THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END AS ElitePostsPercentage,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            (COUNT(CASE WHEN cpa.ViewCount > 100 THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END AS PopularPostsPercentage,
    string_agg(DISTINCT cpa.PostCategory, ', ') AS PostCategories,
    string_agg(DISTINCT cpa.UserActivityLevel, ', ') AS UserActivityLevels,
    string_agg(DISTINCT cpa.AnsweringActivity, ', ') AS AnsweringActivities,
    string_agg(DISTINCT cpa.ViewPerformance, ', ') AS ViewPerformances,
    string_agg(DISTINCT cpa.ScorePerformance, ', ') AS ScorePerformances
FROM ComplexPostAnalysis cpa
WHERE cpa.Score > -10 
  AND cpa.ViewCount >= 0
  AND cpa.CreationDate >= DATE '2020-01-01'
  AND (cpa.OwnerDisplayName IS NOT NULL OR cpa.OwnerUserId IS NULL)
  AND (cpa.PostCategory IS NOT NULL OR cpa.PostTypeId IS NOT NULL)
  AND (
    cpa.Tags IS NULL 
    OR LENGTH(TRIM(cpa.Tags)) > 0
    OR cpa.PostCategory <> 'Other'
  )
  AND (
    cpa.OwnerUserId IS NULL
    OR cpa.OwnerUserId IN (
        SELECT Id FROM Users WHERE Reputation > 500
    )
  )
  AND cpa.ViewCount <= 100000
  AND cpa.Score <= 10000
GROUP BY
    cpa.CreationDate,
    cpa.PostTypeId,
    cpa.OwnerDisplayName,
    cpa.OwnerUserId,
    cpa.PostCategory,
    cpa.Tags,
    cpa.Reputation,
    cpa.UserActivityLevel,
    cpa.AnsweringActivity,
    cpa.ViewPerformance,
    cpa.ScorePerformance,
    cpa.QuestionStatus,
    cpa.PopularityLevel,
    cpa.TagComplexity,
    cpa.ValuePerAnswer,
    cpa.GlobalViewPerformance,
    cpa.UserProfileLevel,
    cpa.ContributorType,
    cpa.UserUpvotedOwnPost,
    cpa.ProcessedTitle,
    cpa.TagAvailability,
    cpa.LogScore,
    cpa.RecentCommentsCount
ORDER BY cpa.CreationDate DESC
LIMIT 1000 OFFSET 1000;