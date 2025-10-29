-- {"query": "1534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3797} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        (CAST(U.Reputation AS numeric) * 0.1 + COALESCE(SUM(P.Score), 0) * 0.05 + COALESCE(SUM(C.Score), 0) * 0.02) AS WeightedEngagementScore,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score ELSE NULL END) OVER (PARTITION BY U.Id) AS AvgPostScoreByUser,
        -- Correlated subquery example: Check if user has any question with score > average of all their posts
        EXISTS (
            SELECT 1
            FROM Posts P_Inner
            WHERE P_Inner.OwnerUserId = U.Id
              AND P_Inner.PostTypeId = 1
              AND P_Inner.Score > (SELECT COALESCE(AVG(P_Sub.Score), 0) FROM Posts P_Sub WHERE P_Sub.OwnerUserId = U.Id AND P_Sub.PostTypeId IN (1, 2))
        ) AS HasHighScoringQuestion
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
PostDetails AS (
    SELECT
        PQ.Id AS PostId,
        PQ.PostTypeId,
        PQ.OwnerUserId,
        PQ.Title,
        PQ.Tags,
        PQ.Body,
        PQ.CreationDate AS PostCreationDate,
        PQ.LastActivityDate AS PostLastActivityDate,
        PQ.Score AS PostScore,
        PQ.ViewCount AS PostViewCount,
        PQ.AnswerCount AS PostAnswerCount,
        PQ.CommentCount AS PostCommentCount,
        PQ.FavoriteCount AS PostFavoriteCount,
        PQ.ClosedDate AS PostClosedDate,
        COUNT(DISTINCT V_Up.Id) AS UpvoteCount,
        COUNT(DISTINCT V_Down.Id) AS DownvoteCount,
        COUNT(DISTINCT V_Fav.Id) AS FavoriteVoteCount,
        COALESCE(SUM(CASE WHEN C.CreationDate > PQ.CreationDate AND C.CreationDate <= PQ.CreationDate + INTERVAL '24' HOUR THEN 1 ELSE 0 END), 0) AS InitialDayCommentCount,
        AVG(PQ.Score) OVER (PARTITION BY PQ.PostTypeId) AS AvgScoreForPostType,
        CASE
            WHEN PQ.PostTypeId = 1 AND PQ.AcceptedAnswerId IS NOT NULL
            THEN 'Has Accepted Answer'
            WHEN PQ.PostTypeId = 1 AND PQ.ClosedDate IS NOT NULL
            THEN 'Closed Question'
            WHEN PQ.PostTypeId = 2 AND PQ.ParentId IS NOT NULL
            THEN 'Answer Post'
            ELSE 'Other Post Type'
        END AS PostStatusDescription,
        COALESCE(
            (SELECT MAX(PH_Edit.CreationDate)
             FROM PostHistory PH_Edit
             WHERE PH_Edit.PostId = PQ.Id AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
            ), PQ.CreationDate) AS LastContentEditDate,
        CASE
            WHEN PQ.PostTypeId = 1 AND LENGTH(COALESCE(PQ.Title, '')) > 50 THEN 'Long Title'
            WHEN PQ.PostTypeId = 1 AND LENGTH(COALESCE(PQ.Title, '')) <= 20 THEN 'Short Title'
            WHEN PQ.PostTypeId = 1 AND LENGTH(COALESCE(PQ.Title, '')) IS NULL THEN 'No Title'
            ELSE 'Normal Title Length'
        END AS TitleLengthCategory,
        CAST(COUNT(CASE WHEN V.VoteTypeId = 5 AND V.UserId IS NOT NULL THEN 1 ELSE NULL END) AS NUMERIC) / NULLIF(COUNT(DISTINCT V.Id), 0) AS FavoriteVoteRatio
    FROM
        Posts PQ
    LEFT JOIN
        Comments C ON PQ.Id = C.PostId
    LEFT JOIN
        Votes V ON PQ.Id = V.PostId
    LEFT JOIN
        Votes V_Up ON PQ.Id = V_Up.PostId AND V_Up.VoteTypeId = 2 -- UpMod
    LEFT JOIN
        Votes V_Down ON PQ.Id = V_Down.PostId AND V_Down.VoteTypeId = 3 -- DownMod
    LEFT JOIN
        Votes V_Fav ON PQ.Id = V_Fav.PostId AND V_Fav.VoteTypeId = 5 -- Favorite
    GROUP BY
        PQ.Id, PQ.PostTypeId, PQ.OwnerUserId, PQ.Title, PQ.Tags, PQ.Body, PQ.CreationDate, PQ.LastActivityDate,
        PQ.Score, PQ.ViewCount, PQ.AnswerCount, PQ.CommentCount, PQ.FavoriteCount, PQ.ClosedDate, PQ.AcceptedAnswerId, PQ.ParentId
),
TagPerformance AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P_Tagged.Id) AS TotalPostsWithTag,
        AVG(P.Score) AS AveragePostScoreForTag,
        MIN(P.CreationDate) AS FirstPostWithTagDate,
        MAX(P.LastActivityDate) AS LastActivityWithTagDate,
        NTILE(5) OVER (ORDER BY AVG(P.Score) DESC, COUNT(DISTINCT P_Tagged.Id) DESC) AS TagScoreQuartile
    FROM
        Tags T
    INNER JOIN
        (SELECT Id, Score, CreationDate, LastActivityDate, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName_parsed FROM Posts WHERE PostTypeId = 1 AND Tags IS NOT NULL) AS P_Tagged ON T.TagName = P_Tagged.TagName_parsed
    INNER JOIN Posts P ON P_Tagged.Id = P.Id
    WHERE
        P.PostTypeId = 1 -- Only consider questions for tag performance
    GROUP BY
        T.TagName
    HAVING
        COUNT(DISTINCT P_Tagged.Id) >= 5 -- Only tags with at least 5 posts
),
PostLifecycleHistory AS (
    SELECT
        PH.PostId,
        MIN(CASE WHEN PH.PostHistoryTypeId = 1 THEN PH.CreationDate ELSE NULL END) AS InitialTitleDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LatestEditDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE NULL END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed' ELSE NULL END) AS WasEverClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened' ELSE NULL END) AS WasEverReopened,
        -- Extract close reason name
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS LastCloseReason,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryEventDate,
        PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS TimeSincePreviousEvent
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS VARCHAR) -- Assuming Comment stores Id as string
    GROUP BY
        PH.PostId
),
-- Set operator example: UNION ALL for two types of "hot" posts
HotPostsCandidate1 AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        'High Engagement Question' AS HotnessCategory,
        COALESCE(UE.WeightedEngagementScore, 0) AS RelatedUserEngagement
    FROM
        Posts P
    INNER JOIN UserEngagement UE ON P.OwnerUserId = UE.UserId
    WHERE
        P.PostTypeId = 1
        AND P.ViewCount > 50000
        AND P.AnswerCount > 10
        AND P.Score > 100
),
HotPostsCandidate2 AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        'Recently Answered by Expert' AS HotnessCategory,
        COALESCE(UE.WeightedEngagementScore, 0) AS RelatedUserEngagement
    FROM
        Posts P
    INNER JOIN UserEngagement UE ON P.OwnerUserId = UE.UserId
    WHERE
        P.PostTypeId = 2 -- An answer
        AND P.CreationDate > NOW() - INTERVAL '30' DAY -- Recent answer
        AND P.Score > 50
        AND UE.Reputation > 20000 -- Answered by a high-reputation user
)
SELECT
    PD.PostId,
    PD.PostTypeId,
    PD.Title,
    PD.PostScore,
    PD.PostViewCount,
    PD.PostAnswerCount,
    PD.PostCommentCount,
    PD.PostFavoriteCount,
    PD.PostCreationDate,
    PD.PostLastActivityDate,
    PD.PostClosedDate,
    PD.UpvoteCount,
    PD.DownvoteCount,
    PD.FavoriteVoteCount,
    PD.InitialDayCommentCount,
    PD.AvgScoreForPostType,
    PD.PostStatusDescription,
    PD.LastContentEditDate,
    PD.TitleLengthCategory,
    UE.UserDisplayName,
    UE.Reputation AS OwnerReputation,
    UE.TotalQuestionsPosted,
    UE.TotalAnswersPosted,
    UE.TotalCommentsMade,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.WeightedEngagementScore,
    UE.AvgPostScoreByUser,
    UE.HasHighScoringQuestion,
    TP.TagName AS MostRelevantTagName,
    TP.AveragePostScoreForTag,
    TP.TotalPostsWithTag,
    TP.TagScoreQuartile,
    PLH.LastCloseReason,
    PLH.WasEverClosed,
    PLH.WasEverReopened,
    PLH.EditCount,
    PLH.TimeSincePreviousEvent,
    -- Example of complex calculation with NULL logic
    COALESCE(
        (CAST(PD.PostScore AS numeric) / NULLIF(PD.PostViewCount, 0) * 100), -- Score per view percentage
        0
    ) AS ScorePerViewRatio,
    -- Example of string expression (tags cleanup and first tag extraction)
    TRIM(
        SUBSTRING(
            PD.Tags,
            POSITION('<' IN PD.Tags) + 1,
            POSITION('>' IN PD.Tags) - POSITION('<' IN PD.Tags) - 1
        )
    ) AS FirstTagInPost,
    PD.FavoriteVoteRatio,
    -- Complex predicate to filter results
    (PD.PostScore > COALESCE(UE.AvgPostScoreByUser, 0) * 1.5 OR PD.PostViewCount > 50000)
    AND PLH.WasEverClosed IS NULL -- Only consider posts that were never closed
    AND PD.PostTypeId = 1 -- Only questions
FROM
    PostDetails PD
INNER JOIN
    UserEngagement UE ON PD.OwnerUserId = UE.UserId
LEFT JOIN LATERAL
    (SELECT TagName_unnested AS TagName, TP_INNER.AveragePostScoreForTag, TP_INNER.TotalPostsWithTag, TP_INNER.TagScoreQuartile
     FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(PD.Tags, 2, LENGTH(PD.Tags)-2), '><')) AS TagName_unnested
     INNER JOIN TagPerformance TP_INNER ON TagName_unnested = TP_INNER.TagName
     ORDER BY TP_INNER.AveragePostScoreForTag DESC, TP_INNER.TotalPostsWithTag DESC
     LIMIT 1
    ) AS TP ON TRUE
LEFT JOIN
    PostLifecycleHistory PLH ON PD.PostId = PLH.PostId
WHERE
    PD.PostCreationDate > '2020-01-01' -- Filter for recent activity
    AND PD.PostTypeId = 1
    AND PD.PostViewCount IS NOT NULL -- Ensure view count is recorded
    AND NOT EXISTS (
        SELECT 1
        FROM Comments C_Sub
        WHERE C_Sub.PostId = PD.PostId
          AND C_Sub.Text LIKE '%spam%'
          AND C_Sub.Score < -2 -- Highly downvoted spam comments
    ) -- Correlated subquery: exclude posts with comments containing "spam" and low score
    AND (PD.PostScore > 50 OR PD.FavoriteCount > 5 OR PD.AnswerCount > 3)
    AND (
        -- NULL logic in predicate
        COALESCE(PD.PostClosedDate, NOW() + INTERVAL '100 year') > NOW() - INTERVAL '1 year' -- Closed date is recent or not closed
    )
UNION ALL
SELECT
    HPC.PostId,
    NULL AS PostTypeId, -- Not directly from PostDetails for these unioned rows
    HPC.Title,
    HPC.Score AS PostScore,
    HPC.ViewCount AS PostViewCount,
    NULL AS PostAnswerCount,
    NULL AS PostCommentCount,
    NULL AS PostFavoriteCount,
    HPC.CreationDate AS PostCreationDate,
    NULL AS PostLastActivityDate,
    NULL AS PostClosedDate,
    NULL AS UpvoteCount,
    NULL AS DownvoteCount,
    NULL AS FavoriteVoteCount,
    NULL AS InitialDayCommentCount,
    NULL AS AvgScoreForPostType,
    HPC.HotnessCategory AS PostStatusDescription, -- Re-purpose for hotness category
    NULL AS LastContentEditDate,
    NULL AS TitleLengthCategory,
    NULL AS UserDisplayName,
    HPC.RelatedUserEngagement AS OwnerReputation, -- Re-purpose for related engagement score
    NULL AS TotalQuestionsPosted,
    NULL AS TotalAnswersPosted,
    NULL AS TotalCommentsMade,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS WeightedEngagementScore,
    NULL AS AvgPostScoreByUser,
    NULL AS HasHighScoringQuestion,
    NULL AS MostRelevantTagName,
    NULL AS AveragePostScoreForTag,
    NULL AS TotalPostsWithTag,
    NULL AS TagScoreQuartile,
    NULL AS LastCloseReason,
    NULL AS WasEverClosed,
    NULL AS WasEverReopened,
    NULL AS EditCount,
    NULL AS TimeSincePreviousEvent,
    NULL AS ScorePerViewRatio,
    NULL AS FirstTagInPost,
    NULL AS FavoriteVoteRatio
FROM
    (SELECT * FROM HotPostsCandidate1 UNION ALL SELECT * FROM HotPostsCandidate2) HPC
ORDER BY
    PostCreationDate DESC, PostScore DESC
LIMIT 1000;