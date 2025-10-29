-- {"query": "1164.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3466} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-level engagement metrics and ranks users by reputation and activity.
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostsScore,
        AVG(COALESCE(P.Score, 0)) AS AvgPostScore,
        (CAST(U.UpVotes AS NUMERIC) - U.DownVotes) AS NetVotesReceived,
        COALESCE(ROUND(CAST(U.UpVotes AS NUMERIC) / NULLIF(U.UpVotes + U.DownVotes, 0), 4), 0) AS VoteSuccessRatio,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 86400 AS DaysSinceUserCreation, -- User age in days
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY U.UpVotes + U.DownVotes DESC, U.Reputation DESC) AS TopVoterPercentile
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate, U.LastAccessDate
),
PostComplexActivity AS (
    -- CTE 2: Calculates various complexity and activity scores for each post, including history, comments, and links.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        COALESCE(P.Title, 'No Title Provided') AS PostTitle,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        P.LastEditorUserId,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN PH.Id END) AS EditCount, -- Title/Body/Tags Edits
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN PH.Id END) AS CloseDeleteLockEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (11, 13, 15) THEN PH.Id END) AS ReopenUndeleteUnlockEvents,
        COUNT(DISTINCT PL.Id) AS TotalPostLinkEntries,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceived, -- Legacy favorites
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS LastCloseReasonId, -- CloseReasonId is in Comment field for type 10
        -- Composite score for post "volatility" or "engagement intensity"
        (
            (COUNT(DISTINCT PH.Id) * 0.75) +
            (COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN PH.Id END) * 1.5) +
            (COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 11, 13, 15) THEN PH.Id END) * 2.5) +
            (COUNT(DISTINCT PL.Id) * 1.0) +
            (COUNT(DISTINCT C.Id) * 0.5) +
            COALESCE(P.FavoriteCount, 0) * 2.0 +
            COALESCE(P.AnswerCount, 0) * 3.0
        ) AS PostEngagementScore,
        -- Detect common problematic or highly discussed tags
        (
            CASE WHEN P.Tags LIKE '%<bug>%' OR P.Tags LIKE '%<error>%' OR P.Tags LIKE '%<design>%' OR P.Tags LIKE '%<performance>%' THEN 1 ELSE 0 END
        ) AS HasFocusTag,
        -- Correlated subquery to fetch last editor's reputation
        (SELECT U2.Reputation FROM Users U2 WHERE U2.Id = P.LastEditorUserId) AS LastEditorReputation,
        -- Correlated subquery to check if the post body contains a specific keyword (case-insensitive)
        (SELECT CASE WHEN P_Main.Body ILIKE '%exception%' THEN TRUE ELSE FALSE END FROM Posts P_Main WHERE P_Main.Id = P.Id) AS ContainsExceptionKeyword
    FROM
        Posts AS P
    LEFT JOIN
        PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN
        PostLinks AS PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    LEFT JOIN
        Votes AS V ON P.Id = V.PostId
    LEFT JOIN
        Comments AS C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.Title, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.CommunityOwnedDate, P.OwnerUserId,
        P.AcceptedAnswerId, P.ParentId, P.Tags, P.LastEditorUserId
),
HighEngagementPosts AS (
    -- CTE 3: Filters and ranks posts based on their engagement score and other criteria, adding close reason details.
    SELECT
        PCA.*,
        CR.Name AS CloseReasonTypeName,
        EXTRACT(EPOCH FROM (NOW() - PCA.PostCreationDate)) / 86400 AS PostAgeDays, -- Post age in days
        RANK() OVER (PARTITION BY PCA.PostTypeId ORDER BY PCA.PostEngagementScore DESC, PCA.ViewCount DESC) AS PostTypeEngagementRank,
        -- NTILE to categorize posts into 4 quartiles based on engagement score
        NTILE(4) OVER (ORDER BY PCA.PostEngagementScore DESC) AS EngagementQuartile,
        -- Calculate length of the post body for text analysis
        LENGTH(P_Main.Body) AS PostBodyLength,
        -- Correlated subquery to check if the owner has a Gold badge
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = PCA.OwnerUserId AND B.Class = 1) AS OwnerHasGoldBadge
    FROM
        PostComplexActivity AS PCA
    LEFT JOIN
        CloseReasonTypes AS CR ON PCA.LastCloseReasonId IS NOT NULL AND CR.Id = CAST(PCA.LastCloseReasonId AS SMALLINT)
    LEFT JOIN
        Posts AS P_Main ON PCA.PostId = P_Main.Id -- Join back to original Posts to get Body
    WHERE
        PCA.PostEngagementScore > 20 -- Minimum engagement score
        AND PCA.ViewCount > 1000
        AND PCA.PostScore >= 10
        AND PCA.PostTypeId IN (1, 2) -- Only Questions or Answers
),
RelevantInteractions AS (
    -- CTE 4: Combines user engagement with their high-engagement posts, adding comparison metrics.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalQuestionsAsked,
        UE.TotalAnswersGiven,
        UE.NetVotesReceived,
        UE.VoteSuccessRatio,
        HEP.PostId,
        HEP.PostTitle,
        HEP.PostCreationDate,
        HEP.PostScore,
        HEP.ViewCount,
        HEP.PostEngagementScore,
        HEP.CloseReasonTypeName,
        HEP.PostAgeDays,
        HEP.EngagementQuartile,
        HEP.PostTypeEngagementRank,
        HEP.OwnerHasGoldBadge,
        HEP.ContainsExceptionKeyword,
        HEP.LastEditorReputation,
        -- Compare current post's engagement to the previous post by the same user (if available)
        LAG(HEP.PostEngagementScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY HEP.PostCreationDate) AS PreviousPostEngagementScore,
        -- Average comment score for the post using a correlated subquery
        (SELECT AVG(COALESCE(C.Score, 0)) FROM Comments C WHERE C.PostId = HEP.PostId AND C.UserId IS NOT NULL) AS AvgCommentScoreByUsers,
        -- String expression: Extract the second tag if it exists, otherwise provide a default value
        COALESCE(
            SUBSTRING(HEP.Tags,
                      STRPOS(HEP.Tags, '>', STRPOS(HEP.Tags, '<') + 1) + 1,
                      STRPOS(HEP.Tags, '>', STRPOS(HEP.Tags, '>', STRPOS(HEP.Tags, '<') + 1) + 1) - (STRPOS(HEP.Tags, '>', STRPOS(HEP.Tags, '<') + 1) + 1)),
            'No Second Tag'
        ) AS SecondTagIfPresent
    FROM
        UserEngagement AS UE
    INNER JOIN
        HighEngagementPosts AS HEP ON UE.UserId = HEP.OwnerUserId
    WHERE
        UE.ReputationRank <= 500 -- Focus on top 500 users by reputation
        AND UE.NetVotesReceived > 100
        AND HEP.EngagementQuartile <= 2 -- Only top 50% most engaging posts
)
-- Main Query: Final selection, aggregation, and complex joins
SELECT
    RI.DisplayName,
    RI.Reputation,
    RI.TotalQuestionsAsked,
    RI.TotalAnswersGiven,
    RI.PostTitle,
    RI.PostScore AS CurrentPostScore,
    RI.ViewCount AS CurrentPostViews,
    RI.PostEngagementScore,
    RI.CloseReasonTypeName,
    RI.PostAgeDays,
    RI.OwnerHasGoldBadge,
    RI.ContainsExceptionKeyword,
    RI.LastEditorReputation,
    RI.PreviousPostEngagementScore,
    RI.AvgCommentScoreByUsers,
    RI.SecondTagIfPresent,
    -- Complicated predicate/calculation: Categorize post based on its score relative to the user's average
    CASE
        WHEN RI.PostScore > (SELECT AVG(PostScore) FROM HighEngagementPosts WHERE OwnerUserId = RI.UserId) * 1.5 THEN 'ExceptionalPostScore'
        WHEN RI.PostScore < (SELECT AVG(PostScore) FROM HighEngagementPosts WHERE OwnerUserId = RI.UserId) * 0.5 THEN 'BelowAvgPostScore'
        ELSE 'AvgRelativePostScore'
    END AS PostScoreRelativeCategory,
    -- LEFT JOIN to PostLinks to find any linked or duplicate posts that are also high engagement
    COALESCE(PL.PostId, PL.RelatedPostId) AS PotentialRelatedPostId,
    COALESCE(LT.Name, 'No Link Type') AS LinkTypeName,
    RelatedHEP.PostTitle AS RelatedPostTitle,
    RelatedHEP.PostEngagementScore AS RelatedPostEngagementScore,
    -- Aggregate gold and silver badges for the user
    STRING_AGG(DISTINCT B.Name, '; ') FILTER (WHERE B.Class = 1) AS UserGoldBadges,
    STRING_AGG(DISTINCT B.Name, '; ') FILTER (WHERE B.Class = 2) AS UserSilverBadges,
    -- Null logic and string operations for Tags (e.g., check for existence of a specific tag)
    CASE
        WHEN RI.Tags LIKE '%<sql>%' OR RI.Tags LIKE '%<database>%' THEN 'SQL/DB Related'
        WHEN RI.Tags IS NULL OR LENGTH(TRIM(RI.Tags)) < 3 THEN 'Untagged/No Tags'
        ELSE 'Other Tags'
    END AS TagCategory
FROM
    RelevantInteractions AS RI
LEFT JOIN
    PostLinks AS PL ON (RI.PostId = PL.PostId OR RI.PostId = PL.RelatedPostId)
LEFT JOIN
    HighEngagementPosts AS RelatedHEP ON (
        (PL.PostId = RelatedHEP.PostId AND PL.RelatedPostId = RI.PostId) OR
        (PL.RelatedPostId = RelatedHEP.PostId AND PL.PostId = RI.PostId)
    ) AND RelatedHEP.EngagementQuartile <= 1 -- Only consider top 25% related posts
LEFT JOIN
    LinkTypes AS LT ON PL.LinkTypeId = LT.Id
LEFT JOIN
    Badges AS B ON RI.UserId = B.UserId
WHERE
    RI.PostTypeEngagementRank <= 10 -- Select only the top 10 engaging posts per post type for these users
    AND (RI.CloseReasonTypeName IS NULL OR RI.CloseReasonTypeName NOT IN ('Duplicate', 'Off-topic', 'Needs details or clarity'))
    AND RI.LastEditorReputation IS NOT NULL AND RI.LastEditorReputation > RI.Reputation * 0.75 -- Last editor has significant rep relative to owner
    AND RI.PreviousPostEngagementScore IS NOT NULL AND RI.PostEngagementScore > RI.PreviousPostEngagementScore * 1.1 -- Post shows improving engagement trend
GROUP BY
    RI.UserId, RI.DisplayName, RI.Reputation, RI.TotalQuestionsAsked, RI.TotalAnswersGiven,
    RI.PostTitle, RI.PostScore, RI.ViewCount, RI.PostEngagementScore, RI.CloseReasonTypeName,
    RI.PostAgeDays, RI.OwnerHasGoldBadge, RI.ContainsExceptionKeyword, RI.LastEditorReputation,
    RI.PreviousPostEngagementScore, RI.AvgCommentScoreByUsers, RI.SecondTagIfPresent,
    PL.PostId, PL.RelatedPostId, LT.Name, RelatedHEP.PostTitle, RelatedHEP.PostEngagementScore,
    RI.Tags, RI.PostTypeEngagementRank, RI.EngagementQuartile
ORDER BY
    RI.Reputation DESC, RI.PostEngagementScore DESC, RI.PostTitle ASC
LIMIT 1000;
