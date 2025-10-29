-- {"query": "1834.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3944} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarizes core user activity and reputation metrics, including complex ratio calculation
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'N/A') AS UserLocation, -- NULL logic (COALESCE)
        U.Views AS ProfileViews,
        U.UpVotes AS TotalGivenUpVotes,
        U.DownVotes AS TotalGivenDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Complicated calculation: Reputation gain per day active, handling potential division by zero
        CAST(U.Reputation AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24), 0) AS RepPerDayActive,
        -- String expression: Extract first 5 chars of upper-cased location
        UPPER(LEFT(COALESCE(U.Location, 'UNKNOWN'), 5)) AS LocationPrefix
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.Views, U.UpVotes, U.DownVotes
),
PostInteractionAggregates AS (
    -- CTE 2: Aggregates votes and comments directly related to posts using outer joins
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.Title,
        P.Tags,
        LENGTH(P.Body) AS BodyLength, -- String expression (LENGTH)
        LENGTH(P.Title) AS TitleLength, -- String expression (LENGTH)
        COUNT(DISTINCT Comm.Id) AS EffectiveCommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount, -- Conditional aggregation
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteBookmarkCount
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Comments Comm ON P.Id = Comm.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, PT.Name, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
             P.FavoriteCount, P.AcceptedAnswerId, P.ParentId, P.LastEditDate, P.LastActivityDate,
             P.ClosedDate, P.CommunityOwnedDate, P.Title, P.Tags, P.Body
),
PostLifecycleStatus AS (
    -- CTE 3: Extracts latest relevant post history events and counts their occurrences.
    -- Includes a correlated subquery to fetch the latest close reason.
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.CreationDate END) AS LastClosedDate_PH,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate_PH,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate END) AS LastDeletedDate_PH,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.Id END) AS CloseEventCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenEventCount,
        -- Correlated subquery example: get the comment of the latest close event
        (
            SELECT PH_sub.Comment
            FROM PostHistory PH_sub
            WHERE PH_sub.PostId = PH.PostId
              AND PH_sub.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
            ORDER BY PH_sub.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReasonComment
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 16, 101, 102, 103, 104, 105)
    GROUP BY PH.PostId
),
PostLinkAnalysis AS (
    -- CTE 4: Analyzes linked and duplicate posts using specific LinkTypes
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS DuplicatePostCount,
        MAX(CASE WHEN PL_Linked.LinkTypeId = 1 THEN PL_Linked.CreationDate END) AS LatestLinkedDate,
        MAX(CASE WHEN PL_Duplicate.LinkTypeId = 3 THEN PL_Duplicate.CreationDate END) AS LatestDuplicateDate
    FROM Posts P
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 -- LinkType=1 for Linked posts
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 -- LinkType=3 for Duplicate posts
    GROUP BY P.Id
),
TagUsageMetrics AS (
    -- CTE 5: Calculates performance metrics for tags. Utilizes string_to_array and CROSS JOIN LATERAL for tag parsing.
    SELECT
        Tag.TagName,
        COUNT(DISTINCT PI.PostId) AS TaggedPostCount,
        AVG(PI.Score) AS AvgScoreForTag,
        SUM(PI.ViewCount) AS TotalViewsForTag,
        -- Complicated calculation: Score to view ratio
        (CAST(SUM(PI.Score) AS NUMERIC) / NULLIF(SUM(PI.ViewCount), 0)) AS ScoreToViewRatio,
        MAX(PI.PostCreationDate) AS LatestPostInTag
    FROM PostInteractionAggregates PI
    -- String expression: parsing tags from the 'Tags' column
    CROSS JOIN LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM PI.Tags), '><')) AS Tag(TagName)
    WHERE PI.PostTypeId = 1 -- Typically questions have tags
    GROUP BY Tag.TagName
    HAVING COUNT(DISTINCT PI.PostId) > 50 -- Filter out less common tags
),
FullPostContext AS (
    -- CTE 6: Combines all post-related information and applies complex conditional logic
    SELECT
        PIA.PostId,
        PIA.OwnerUserId,
        COALESCE(UAS.DisplayName, PIA.OwnerUserId::varchar) AS PostOwnerDisplayName, -- NULL logic, type casting
        PIA.PostTypeId,
        PIA.PostTypeName,
        PIA.PostCreationDate,
        PIA.Score,
        PIA.ViewCount,
        PIA.UpvoteCount,
        PIA.DownvoteCount,
        PIA.FavoriteBookmarkCount,
        PIA.EffectiveCommentCount,
        PIA.BodyLength,
        PIA.TitleLength,
        PIA.AcceptedAnswerId,
        PIA.ParentId,
        -- NULL logic: Coalescing Post.ClosedDate with PostHistory.LastClosedDate
        COALESCE(PIA.ClosedDate, PLS.LastClosedDate_PH) AS EffectiveClosedDate,
        PLS.LastReopenedDate_PH,
        PLS.LastDeletedDate_PH,
        PLS.CloseEventCount,
        PLS.ReopenEventCount,
        PLS.LatestCloseReasonComment,
        PLA.LinkedPostCount,
        PLA.DuplicatePostCount,
        -- Date calculation: Days since last activity
        EXTRACT(DAY FROM AGE(NOW(), COALESCE(PIA.LastActivityDate, PIA.PostCreationDate))) AS DaysSinceLastActivity,
        -- Complicated predicate/expression (CASE statement for post categorization)
        CASE
            WHEN PIA.PostTypeId = 1 AND PIA.AcceptedAnswerId IS NOT NULL THEN 'Question_Accepted'
            WHEN PIA.PostTypeId = 1 AND PIA.AcceptedAnswerId IS NULL AND PIA.AnswerCount > 0 THEN 'Question_UnacceptedAnswers'
            WHEN PIA.PostTypeId = 1 AND PIA.AnswerCount = 0 THEN 'Question_NoAnswers'
            WHEN PIA.PostTypeId = 2 AND PIA.ParentId IS NOT NULL THEN 'Answer'
            WHEN PIA.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'OtherPostType'
        END AS PostCategory,
        -- Complicated calculation: Post Upvote Ratio, handling division by zero
        (CAST(PIA.UpvoteCount AS NUMERIC) / NULLIF(PIA.UpvoteCount + PIA.DownvoteCount, 0)) AS PostUpvoteRatio
    FROM PostInteractionAggregates PIA
    LEFT JOIN UserActivitySummary UAS ON PIA.OwnerUserId = UAS.UserId
    LEFT JOIN PostLifecycleStatus PLS ON PIA.PostId = PLS.PostId
    LEFT JOIN PostLinkAnalysis PLA ON PIA.PostId = PLA.PostId
    WHERE PIA.OwnerUserId IS NOT NULL -- Exclude community owned posts without a specific owner for this analysis
),
AggregatedUserContext AS (
    -- CTE 7: Integrates user summary with post context, applying various window functions
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.UserCreationDate,
        UAS.ProfileViews,
        UAS.RepPerDayActive,
        UAS.LocationPrefix,
        FPC.PostId,
        FPC.PostOwnerDisplayName,
        FPC.PostTypeName,
        FPC.PostCreationDate,
        FPC.Score,
        FPC.ViewCount,
        FPC.UpvoteCount,
        FPC.DownvoteCount,
        FPC.PostUpvoteRatio,
        FPC.BodyLength,
        FPC.TitleLength,
        FPC.EffectiveClosedDate,
        FPC.LastReopenedDate_PH,
        FPC.LatestCloseReasonComment,
        FPC.LinkedPostCount,
        FPC.DuplicatePostCount,
        FPC.DaysSinceLastActivity,
        FPC.PostCategory,
        -- Window Functions:
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId ORDER BY FPC.Score DESC, FPC.ViewCount DESC) AS UserPostScoreRank,
        AVG(FPC.Score) OVER (PARTITION BY FPC.PostTypeId) AS GlobalAvgScoreForPostType,
        SUM(FPC.ViewCount) OVER (PARTITION BY UAS.UserId ORDER BY FPC.PostCreationDate) AS CumulativeUserPostViews,
        LAG(FPC.Score, 1, 0) OVER (PARTITION BY UAS.UserId ORDER BY FPC.PostCreationDate) AS PrevPostScore, -- LAG
        LEAD(FPC.Score, 1, 0) OVER (PARTITION BY UAS.UserId ORDER BY FPC.PostCreationDate) AS NextPostScore, -- LEAD
        NTH_VALUE(FPC.Score, 2) OVER (PARTITION BY UAS.UserId ORDER BY FPC.Score DESC) AS SecondHighestPostScore -- NTH_VALUE
    FROM UserActivitySummary UAS
    INNER JOIN FullPostContext FPC ON UAS.UserId = FPC.OwnerUserId
)
-- Main Query: Selects combined data, applies further filtering, and uses set operators (UNION ALL)
SELECT
    AUC.UserId,
    AUC.DisplayName,
    AUC.Reputation,
    AUC.UserCreationDate,
    AUC.LocationPrefix,
    AUC.PostId,
    AUC.PostTypeName,
    AUC.Score,
    AUC.ViewCount,
    AUC.UpvoteCount,
    AUC.DownvoteCount,
    AUC.PostUpvoteRatio,
    AUC.PostCategory,
    AUC.EffectiveClosedDate,
    AUC.LatestCloseReasonComment,
    AUC.UserPostScoreRank,
    AUC.GlobalAvgScoreForPostType,
    AUC.CumulativeUserPostViews,
    AUC.PrevPostScore,
    AUC.NextPostScore,
    AUC.SecondHighestPostScore,
    TUM.TagName AS PrimaryAssociatedTag,
    TUM.AvgScoreForTag AS PrimaryTagAvgScore,
    'High-Engagement_Question' AS AnalysisType -- Discriminator for UNION ALL
FROM AggregatedUserContext AUC
LEFT JOIN ( -- Subquery to find the primary tag for each post (based on highest average score)
    SELECT
        PostId,
        TagName,
        AvgScoreForTag
    FROM (
        SELECT
            PI.PostId,
            TUM_sub.TagName,
            TUM_sub.AvgScoreForTag,
            ROW_NUMBER() OVER (PARTITION BY PI.PostId ORDER BY TUM_sub.AvgScoreForTag DESC, TUM_sub.TotalViewsForTag DESC) as rn
        FROM PostInteractionAggregates PI
        CROSS JOIN LATERAL UNNEST(string_to_array(TRIM(BOTH '<>' FROM PI.Tags), '><')) AS Tag(TagName)
        INNER JOIN TagUsageMetrics TUM_sub ON Tag.TagName = TUM_sub.TagName
        WHERE PI.Tags IS NOT NULL AND PI.PostTypeId = 1
    ) AS RankedTagsPerPost
    WHERE rn = 1
) AS TUM ON AUC.PostId = TUM.PostId
WHERE
    AUC.Reputation >= 5000
    AND AUC.PostTypeName = 'Question'
    AND AUC.PostUpvoteRatio > 0.8
    AND AUC.DaysSinceLastActivity < 365
    AND AUC.UserPostScoreRank <= 5
    AND AUC.Score > AUC.GlobalAvgScoreForPostType -- Correlated subquery concept (here, comparison to a window aggregate)
    AND AUC.EffectiveClosedDate IS NULL -- NULL logic (IS NULL)
    AND NOT EXISTS ( -- Correlated subquery: Check if post has any "Spam" or "Offensive" votes
        SELECT 1
        FROM Votes V_sub
        WHERE V_sub.PostId = AUC.PostId
          AND V_sub.VoteTypeId IN (4, 12) -- Offensive, Spam
    )
    AND (
        AUC.BodyLength > 500
        OR
        POSITION('code' IN LOWER(AUC.Title)) > 0 -- String expression (LOWER, POSITION)
    )

UNION ALL -- Set operator: Combines two distinct result sets

SELECT
    AUC.UserId,
    AUC.DisplayName,
    AUC.Reputation,
    AUC.UserCreationDate,
    AUC.LocationPrefix,
    AUC.PostId,
    AUC.PostTypeName,
    AUC.Score,
    AUC.ViewCount,
    AUC.UpvoteCount,
    AUC.DownvoteCount,
    AUC.PostUpvoteRatio,
    AUC.PostCategory,
    AUC.EffectiveClosedDate,
    AUC.LatestCloseReasonComment,
    AUC.UserPostScoreRank,
    AUC.GlobalAvgScoreForPostType,
    AUC.CumulativeUserPostViews,
    AUC.PrevPostScore,
    AUC.NextPostScore,
    AUC.SecondHighestPostScore,
    NULL AS PrimaryAssociatedTag, -- Tags not directly linked to answers in the same way for this analysis part
    NULL AS PrimaryTagAvgScore,
    'High-Engagement_Answer' AS AnalysisType -- Discriminator for UNION ALL
FROM AggregatedUserContext AUC
WHERE
    AUC.Reputation BETWEEN 1000 AND 4999
    AND AUC.PostTypeName = 'Answer'
    AND AUC.Score > 50
    AND AUC.DaysSinceLastActivity < 180
    AND AUC.PostUpvoteRatio > 0.9
    AND AUC.LinkedPostCount = 0
    AND AUC.EffectiveClosedDate IS NULL
    AND EXISTS ( -- Correlated subquery: Check if the answer's parent question has at least 3 answers
        SELECT 1
        FROM Posts Q_sub
        WHERE Q_sub.Id = AUC.ParentId
          AND Q_sub.PostTypeId = 1
          AND Q_sub.AnswerCount >= 3
    )
ORDER BY
    Reputation DESC,
    Score DESC,
    DaysSinceLastActivity ASC
LIMIT 2000;
