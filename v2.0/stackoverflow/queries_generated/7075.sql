-- {"query": "7075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3306} 
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
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(trim(p.Tags, '<>'), '><')) AS tag) 
                 WHERE tag IS NOT NULL AND tag != '')
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
    WHERE p.CreationDate >= '2019-01-01' 
),
PostWithUserDetails AS (
    SELECT 
        ps.*,
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
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN 
                (CASE WHEN ps.TagCount > 3 THEN 'TagRich' WHEN ps.TagCount > 1 THEN 'TagModerate' ELSE 'TagSparse' END)
            ELSE 'NoTags'
        END AS TagComplexity
    FROM PostStats ps
    LEFT JOIN Users u ON ps.OwnerUserId = u.Id
    WHERE ps.PostTypeId IN (1, 2) 
),
AnswerStats AS (
    SELECT 
        ps.*,
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
        as1.*,
        CASE 
            WHEN as1.Tags IS NOT NULL AND as1.Tags != '' THEN 
                (SELECT STRING_AGG(tag, ', ') 
                 FROM unnest(string_to_array(trim(trim(as1.Tags, '<>'), '><')) AS tag 
                 WHERE tag IS NOT NULL AND tag != '')
            ELSE 'No Tags' 
        END AS TagList,
        CASE 
            WHEN as1.Tags IS NOT NULL AND as1.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(trim(trim(as1.Tags, '<>'), '><')) AS tag WHERE tag IS NOT NULL AND tag != '')
            ELSE 0 
        END AS TagCountFinal
    FROM AnswerStats as1
),
UserPostSummary AS (
    SELECT 
        qt.*,
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
        ups.*,
        (ups.Score * ups.AnswerCountCoalesced) AS ScoreAnswerProduct,
        (ups.ViewCount * ups.FavoriteCount) AS ViewFavoriteProduct,
        (ups.TagCountFinal * ups.Score) AS TagScoreRatio,
        CASE 
            WHEN ups.Score > 0 AND ups.AnswerCountCoalesced > 0 THEN
                CASE 
                    WHEN ups.Score / ups.AnswerCountCoalesced > 5 THEN 'HighValue'
                    WHEN ups.Score / ups.AnswerCountCoalesced BETWEEN 1 AND 5 THEN 'MediumValue'
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
        -- Window function comparison with entire dataset
        RANK() OVER (ORDER BY ups.Score DESC) - ROW_NUMBER() OVER (ORDER BY ups.Score DESC) AS ScoreRankDeviation,
        -- Set operations to find special cases
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
        -- Correlated subquery for complex condition
        COALESCE(
            (SELECT 1 FROM Votes v WHERE v.PostId = ups.Id AND v.VoteTypeId = 2 AND v.UserId = ups.OwnerUserId),
            0
        ) AS UserUpvotedOwnPost,
        -- String expression processing
        CASE 
            WHEN ups.Title IS NOT NULL THEN 
                TRIM(UPPER(LEFT(ups.Title, 100)) || '...' || RIGHT(ups.Title, 50))
            ELSE 'No Title Available'
        END AS ProcessedTitle,
        -- NULL checking and handling
        CASE 
            WHEN ups.Tags IS NULL OR ups.Tags = '' THEN 'No Tags Provided'
            ELSE 'Tags Present'
        END AS TagAvailability,
        -- Mathematical calculation and expression
        ROUND(
            (CASE WHEN ups.Score > 0 THEN LOG(ups.Score) ELSE 0 END), 
            2
        ) AS LogScore,
        -- Complex window function
        LAG(ups.Score, 1, 0) OVER (
            PARTITION BY ups.OwnerUserId 
            ORDER BY ups.CreationDate ASC
        ) AS PreviousPostScore,
        -- Multi-table join and filtering
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ups.Id 
             AND c.CreationDate >= ups.CreationDate - INTERVAL '7 days'
            ), 0
        ) AS RecentCommentsCount
    FROM UserPostSummary ups
)
-- Final selection with multiple complex conditions and aggregations
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
    STRING_AGG(DISTINCT cpa.QuestionStatus, ', ') AS QuestionStatuses,
    STRING_AGG(DISTINCT cpa.PopularityLevel, ', ') AS PopularityLevels,
    COUNT(DISTINCT cpa.OwnerUserId) AS UniqueUsers,
    STRING_AGG(DISTINCT cpa.TagComplexity, ', ') AS TagComplexities,
    STRING_AGG(DISTINCT cpa.ValuePerAnswer, ', ') AS ValuePerAnswers,
    STRING_AGG(DISTINCT cpa.GlobalViewPerformance, ', ') AS GlobalViewPerformances,
    STRING_AGG(DISTINCT cpa.UserProfileLevel, ', ') AS UserProfileLevels,
    STRING_AGG(DISTINCT cpa.ContributorType, ', ') AS ContributorTypes,
    COUNT(CASE WHEN cpa.UserUpvotedOwnPost = 1 THEN 1 END) AS SelfUpvotedPosts,
    COUNT(CASE WHEN cpa.ProcessedTitle != 'No Title Available' THEN 1 END) AS PostsWithTitle,
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
    STRING_AGG(DISTINCT cpa.PostCategory, ', ') AS PostCategories,
    STRING_AGG(DISTINCT cpa.UserActivityLevel, ', ') AS UserActivityLevels,
    STRING_AGG(DISTINCT cpa.AnsweringActivity, ', ') AS AnsweringActivities,
    STRING_AGG(DISTINCT cpa.ViewPerformance, ', ') AS ViewPerformances,
    STRING_AGG(DISTINCT cpa.ScorePerformance, ', ') AS ScorePerformances
FROM ComplexPostAnalysis cpa
WHERE cpa.Score > -10 
  AND cpa.ViewCount >= 0
  AND cpa.CreationDate >= '2020-01-01'
  AND (cpa.OwnerDisplayName IS NOT NULL OR cpa.OwnerUserId IS NULL)
  AND (cpa.PostCategory IS NOT NULL OR cpa.PostTypeId IS NOT NULL)
  AND (
    cpa.Tags IS NULL 
    OR LENGTH(TRIM(cpa.Tags)) > 0
    OR cpa.PostCategory != 'Other'
  )
  AND (
    cpa.OwnerUserId IS NULL
    OR cpa.OwnerUserId IN (
        SELECT Id FROM Users WHERE Reputation > 500
    )
  )
  AND cpa.ViewCount <= 100000
  AND cpa.Score <= 10000
ORDER BY cpa.CreationDate DESC
LIMIT 1000 OFFSET 1000;