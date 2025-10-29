-- {"query": "1209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3472} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        -- Aggregate function with FILTER clause (PostgreSQL-specific)
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Window function: Rank users by reputation
        RANK() OVER (ORDER BY U.Reputation DESC, U.Id ASC) AS ReputationRank,
        -- Correlated Subquery: Check if user has any badges named 'Enthusiast' or 'Fanatic'
        EXISTS (SELECT 1 FROM Badges B_sub WHERE B_sub.UserId = U.Id AND B_sub.Name IN ('Enthusiast', 'Fanatic')) AS HasEngagementBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.CreationDate, U.LastAccessDate, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount AS OriginalAnswerCount,
        P.CommentCount AS OriginalCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.ParentId,
        P.AcceptedAnswerId,
        P.CommunityOwnedDate,
        -- String expression and NULL logic: Extract primary tag, or assign 'untagged'
        COALESCE(SUBSTRING(P.Tags, 2, POSITION('><' IN P.Tags || '><') - 2), 'untagged') AS PrimaryTag,
        -- Complicated calculation: Post Activity Score
        (P.Score * 5 + COALESCE(P.ViewCount, 0) / 10 + COALESCE(P.CommentCount, 0) * 2 + COALESCE(P.FavoriteCount, 0) * 10) AS PostActivityScore,
        -- Correlated Subquery: Count of unique users who upvoted this post in the last year
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 2 AND V.CreationDate >= P.CreationDate - INTERVAL '1 year') AS RecentUpVotersCount,
        -- Window function: Average score of posts of the same type created in the same month
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId, DATE_TRUNC('month', P.CreationDate)) AS AvgPostTypeScoreInMonth,
        -- Window function: Time difference in days to previous post by the same owner
        EXTRACT(EPOCH FROM (P.CreationDate - LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate))) / 86400 AS DaysSincePreviousPost
    FROM Posts AS P
    JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate >= '2020-01-01' -- Filter for more recent post data
),
ModerationOverview AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PHT.Name AS HistoryTypeName,
        CR.Name AS CloseReasonName,
        PH.UserId AS ModifierUserId,
        PH.Comment,
        -- String expression and NULL logic: Extract target post IDs from Text for duplicates (JSON parsing)
        COALESCE(
            NULLIF(
                SUBSTRING(PH.Text, POSITION('"OriginalQuestionIds":[' IN PH.Text) + LENGTH('"OriginalQuestionIds":['),
                POSITION(']' IN PH.Text) - (POSITION('"OriginalQuestionIds":[' IN PH.Text) + LENGTH('"OriginalQuestionIds":[']))
                , '')
            , NULL
        ) AS OriginalQuestionIdsText,
        -- Complicated Predicate: Categorize moderation types based on history ID
        CASE
            WHEN PH.PostHistoryTypeId IN (10, 101) THEN 'Closed'
            WHEN PH.PostHistoryTypeId IN (11, 102) THEN 'Reopened'
            WHEN PH.PostHistoryTypeId = 12 THEN 'Deleted'
            WHEN PH.PostHistoryTypeId = 13 THEN 'Undeleted'
            WHEN PH.PostHistoryTypeId = 14 THEN 'Locked'
            WHEN PH.PostHistoryTypeId = 35 THEN 'Migrated Away'
            ELSE 'OtherModeration'
        END AS ModerationEventType,
        -- Window function: Rank moderation events per post by date
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_moderation
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes AS CR ON PH.PostHistoryTypeId IN (10, 101) AND PH.Comment IS NOT NULL AND CR.Id = CAST(PH.Comment AS smallint)
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 35, 101, 102) -- Focus on specific moderation actions
),
PostCommentScores AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        AVG(C.Score) AS AverageCommentScore,
        SUM(CASE WHEN C.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentsCount,
        -- Correlated subquery: Check if any comment contains 'thanks' or 'thank you' (case-insensitive)
        EXISTS (SELECT 1 FROM Comments AS C2 WHERE C2.PostId = C.PostId AND (C2.Text ILIKE '%thank you%' OR C2.Text ILIKE '%thanks%')) AS HasGratitudeComment,
        -- String expression: Concatenate text of top 3 highest-scoring comments
        (SELECT STRING_AGG(C3.Text, ' || ') FROM Comments AS C3 WHERE C3.PostId = C.PostId ORDER BY C3.Score DESC LIMIT 3) AS TopCommentsPreview
    FROM Comments AS C
    GROUP BY C.PostId
),
TagMetrics AS (
    SELECT
        TagName,
        COUNT(DISTINCT P.Id) AS PostsWithTag,
        AVG(P.Score) AS AvgScoreForTag,
        SUM(P.ViewCount) AS TotalViewsForTag,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueOwnersForTag
    FROM Posts AS P, UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TagName
)
-- Main Query Combining Insights - Part 1: Active user/post analysis
SELECT
    'ActiveUserPostInsight' AS InsightType,
    UA.UserId,
    COALESCE(UA.DisplayName, 'Unknown User') AS UserName,
    UA.Reputation,
    UA.TotalPosts,
    UA.QuestionCount,
    UA.AnswerCount,
    UA.AvgPostScore,
    UA.GoldBadges,
    UA.SilverBadges,
    UA.ReputationRank,
    PD.PostId,
    PD.PostTypeName,
    PD.Title,
    PD.PostScore,
    PD.ViewCount,
    PD.PostActivityScore,
    PD.RecentUpVotersCount,
    PD.AvgPostTypeScoreInMonth,
    PD.DaysSincePreviousPost,
    COALESCE(PCS.TotalCommentsOnPost, 0) AS PostCommentCount,
    COALESCE(PCS.AverageCommentScore, 0.0) AS PostAvgCommentScore,
    PCS.HasGratitudeComment,
    MO.HistoryTypeName AS LastModerationAction,
    MO.CloseReasonName,
    MO.OriginalQuestionIdsText,
    PCS.TopCommentsPreview,
    TM.PostsWithTag AS PrimaryTagPostsCount,
    TM.AvgScoreForTag AS PrimaryTagAvgScore,
    TM.UniqueOwnersForTag AS PrimaryTagUniqueOwners,
    -- NULL logic: Determine post status based on ClosedDate
    CASE
        WHEN PD.ClosedDate IS NULL THEN 'Open'
        WHEN PD.CommunityOwnedDate IS NOT NULL THEN 'Community Owned & Closed'
        ELSE 'Closed'
    END AS PostStatus,
    -- Complicated predicate: Check if post is a duplicate, linked, or neither (using PostLinks)
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = PD.PostId AND PL.LinkTypeId = 3) THEN 'Duplicate Source'
        WHEN EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.RelatedPostId = PD.PostId AND PL.LinkTypeId = 3) THEN 'Duplicate Target'
        WHEN EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = PD.PostId AND PL.LinkTypeId = 1) THEN 'Linked'
        ELSE 'Not Linked/Duplicate'
    END AS LinkStatus,
    -- Calculate a "User Engagement Score" combining reputation, posts, comments, and votes
    CAST(UA.Reputation AS DECIMAL) / 100.0 + (UA.TotalPosts * 5) + (UA.TotalComments * 2) + (UA.UserUpVotes - UA.UserDownVotes) AS UserEngagementScore,
    UA.HasEngagementBadges AS UserHasEngagementBadges
FROM UserActivity AS UA
LEFT JOIN PostDetails AS PD ON UA.UserId = PD.OwnerUserId
LEFT JOIN PostCommentScores AS PCS ON PD.PostId = PCS.PostId
LEFT JOIN ModerationOverview AS MO ON PD.PostId = MO.PostId AND MO.rn_latest_moderation = 1 -- Only latest moderation event
LEFT JOIN TagMetrics AS TM ON PD.PrimaryTag = TM.TagName
WHERE
    UA.Reputation > 1000 -- Filter for more established users
    AND PD.PostActivityScore > 50 -- Filter for reasonably active posts
    AND (
        PD.PostTypeName = 'Question' AND PD.OriginalAnswerCount >= 1
        OR
        PD.PostTypeName = 'Answer' AND PD.PostScore > 0
    )
    AND (PD.ClosedDate IS NULL OR PD.ClosedDate > PD.CreationDate + INTERVAL '1 month') -- Exclude quickly closed posts
    AND NOT (PD.PostTypeName = 'Answer' AND PD.ParentId IS NULL) -- Exclude orphaned answers (shouldn't exist but for robustness)

UNION ALL

-- Main Query Combining Insights - Part 2: "Hidden Gems" or "Overlooked" Posts
-- This segment identifies posts with high scores but low views, or vice versa, from active users
SELECT
    'HiddenGemOrOverlooked' AS InsightType,
    UA.UserId,
    COALESCE(UA.DisplayName, 'Unknown User') AS UserName,
    UA.Reputation,
    UA.TotalPosts,
    UA.QuestionCount,
    UA.AnswerCount,
    UA.AvgPostScore,
    UA.GoldBadges,
    UA.SilverBadges,
    UA.ReputationRank,
    PD.PostId,
    PD.PostTypeName,
    PD.Title,
    PD.PostScore,
    PD.ViewCount,
    PD.PostActivityScore,
    PD.RecentUpVotersCount,
    PD.AvgPostTypeScoreInMonth,
    PD.DaysSincePreviousPost,
    COALESCE(PCS.TotalCommentsOnPost, 0) AS PostCommentCount,
    COALESCE(PCS.AverageCommentScore, 0.0) AS PostAvgCommentScore,
    PCS.HasGratitudeComment,
    NULL AS LastModerationAction, -- Not directly relevant for this specific segment
    NULL AS CloseReasonName,
    NULL AS OriginalQuestionIdsText,
    PCS.TopCommentsPreview,
    TM.PostsWithTag AS PrimaryTagPostsCount,
    TM.AvgScoreForTag AS PrimaryTagAvgScore,
    TM.UniqueOwnersForTag AS PrimaryTagUniqueOwners,
    CASE
        WHEN PD.ClosedDate IS NULL THEN 'Open'
        WHEN PD.CommunityOwnedDate IS NOT NULL THEN 'Community Owned & Closed'
        ELSE 'Closed'
    END AS PostStatus,
    'N/A' AS LinkStatus, -- Not calculating link status for this segment
    CAST(UA.Reputation AS DECIMAL) / 100.0 + (UA.TotalPosts * 5) + (UA.TotalComments * 2) + (UA.UserUpVotes - UA.UserDownVotes) AS UserEngagementScore,
    UA.HasEngagementBadges AS UserHasEngagementBadges
FROM UserActivity AS UA
INNER JOIN PostDetails AS PD ON UA.UserId = PD.OwnerUserId
LEFT JOIN PostCommentScores AS PCS ON PD.PostId = PCS.PostId
LEFT JOIN TagMetrics AS TM ON PD.PrimaryTag = TM.TagName
WHERE
    UA.Reputation > 500 -- Slightly less strict for overlooked posts
    AND (
        (PD.PostScore >= 5 AND PD.ViewCount < 500) -- "Hidden Gem": good score, low views
        OR
        (PD.PostScore < 0 AND PD.ViewCount > 2000) -- "Controversial/Overlooked": negative score, high views
    )
    AND PD.PostCreationDate >= '2021-01-01' -- Focus on more recent "gems" or "overlooked" posts
ORDER BY
    ReputationRank ASC,
    PostActivityScore DESC,
    PostCreationDate DESC
LIMIT 2000; -- Limit the total combined output for practical benchmarking
```