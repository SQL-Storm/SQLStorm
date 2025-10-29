-- {"query": "1977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2760} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViewsReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        U.LastAccessDate,
        -- Calculate average daily reputation gain, handling division by zero
        CASE
            WHEN (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24)) > 0
            THEN U.Reputation / (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24))
            ELSE 0.0
        END AS AvgDailyReputation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEventSummary AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS FirstEditEventDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id ELSE NULL END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id ELSE NULL END) AS ReopenCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastCloseEventDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenEventDate
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.LastEditDate, P.ClosedDate
),
TagPopularityAndQuality AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostCount,
        COALESCE(SUM(P.Score), 0) AS TotalTagScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalTagViews,
        AVG(P.Score) AS AvgTagPostScore,
        AVG(P.ViewCount) AS AvgTagPostViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TaggedQuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TaggedAnswerCount
    FROM Posts AS P
    -- Explode tags from string into individual rows using string_to_array and UNNEST
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS TagAlias (TagName) ON TRUE
    JOIN Tags AS T ON TagAlias.TagName = T.TagName
    WHERE P.Tags IS NOT NULL AND P.Tags != '' AND P.PostTypeId IN (1, 2)
    GROUP BY T.TagName
),
VoteAnalytics AS (
    SELECT
        P.Id AS PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount_Actual, -- Pre-Oct 2022 actual favorite votes
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN V.VoteTypeId = 9 THEN V.BountyAmount ELSE 0 END) AS TotalBountyReceived
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    GROUP BY P.Id
)
SELECT
    UAS.UserId,
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalPostScoreReceived,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.AvgDailyReputation,
    P.Id AS PostId,
    P.Title AS PostTitle,
    PT.Name AS PostTypeName,
    P.CreationDate AS PostDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.AnswerCount,
    P.CommentCount AS PostCommentCount,
    P.FavoriteCount AS PostFavoriteCount_Metadata, -- FavoriteCount from the Posts table (metadata, not actual votes)
    COALESCE(PES.EditCount, 0) AS PostEditCount,
    COALESCE(PES.CloseCount, 0) AS PostCloseCount,
    COALESCE(PES.ReopenCount, 0) AS PostReopenCount,
    COALESCE(VA.UpvoteCount, 0) AS PostActualUpvoteCount,
    COALESCE(VA.DownvoteCount, 0) AS PostActualDownvoteCount,
    COALESCE(VA.FavoriteCount_Actual, 0) AS PostActualFavoriteVoteCount,
    COALESCE(VA.TotalBountyReceived, 0) AS PostTotalBountyReceived,
    COALESCE(TPQ_Main.AvgTagPostScore, 0.0) AS MainTagAvgScore,
    COALESCE(TPQ_Main.TaggedPostCount, 0) AS MainTagTotalPosts,
    -- Window function: Rank users by reputation within their creation year
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UAS.UserCreationDate) ORDER BY UAS.Reputation DESC, UAS.UserId) AS RankInCreationYear,
    -- Window function: Average score of posts by the same user for the same post type
    AVG(P.Score) OVER (PARTITION BY UAS.UserId, P.PostTypeId) AS UserAvgPostScoreForType,
    -- Complicated calculation with NULL logic: Time elapsed since last edit (if edited), else time since creation
    COALESCE(
        EXTRACT(EPOCH FROM (NOW() - PES.LastEditEventDate)) / (60 * 60 * 24), -- Days since last edit
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60 * 60 * 24)        -- Days since creation
    ) AS DaysSinceLastActivityOrCreation,
    -- String expression: Truncate Body if too long, indicating if it was truncated
    SUBSTRING(P.Body, 1, 200) || CASE WHEN LENGTH(P.Body) > 200 THEN '...' ELSE '' END AS PostBodyExcerpt,
    -- NULL logic and complicated predicate: Categorize post based on closure, comment count, and owner's reputation
    CASE
        WHEN P.ClosedDate IS NOT NULL
             AND P.CommentCount > 5
             AND UAS.Reputation < 1000
        THEN 'Closed_Engaged_LowRepUser'
        WHEN P.ClosedDate IS NOT NULL
             AND P.CommentCount > 0
             AND UAS.Reputation >= 1000
        THEN 'Closed_ActiveHighRepUser'
        WHEN P.ClosedDate IS NULL AND P.AcceptedAnswerId IS NOT NULL AND P.AnswerCount > 0
             AND (SELECT COUNT(C2.Id) FROM Comments AS C2 WHERE C2.PostId = P.Id AND C2.CreationDate > P.CreationDate) > 2 -- Correlated subquery: count comments after post creation
        THEN 'Answered_Engaged'
        WHEN P.CommunityOwnedDate IS NOT NULL
             AND P.LastEditDate > (P.CreationDate + INTERVAL '90 days')
        THEN 'CommunityOwned_LongLived'
        ELSE 'Other_Status'
    END AS PostStatusCategory,
    -- Correlated subquery to check if the user had any gold badges *before* the post was created
    (SELECT EXISTS (SELECT 1 FROM Badges AS B2 WHERE B2.UserId = UAS.UserId AND B2.Class = 1 AND B2.Date < P.CreationDate)) AS UserHadGoldBadgeBeforePost
FROM Users AS U
JOIN UserActivitySummary AS UAS ON U.Id = UAS.UserId
LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
LEFT JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
LEFT JOIN PostEventSummary AS PES ON P.Id = PES.PostId
LEFT JOIN VoteAnalytics AS VA ON P.Id = VA.PostId
LEFT JOIN ( -- Subquery to identify the primary tag for questions (first tag listed)
    SELECT
        DISTINCT ON (P_Inner.Id)
        P_Inner.Id AS PostId,
        TagAlias_Inner.TagName AS PrimaryTagName
    FROM Posts AS P_Inner
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P_Inner.Tags FROM 2 FOR LENGTH(P_Inner.Tags)-2), '><')) AS TagAlias_Inner (TagName) ON TRUE
    WHERE P_Inner.PostTypeId = 1 AND P_Inner.Tags IS NOT NULL AND P_Inner.Tags != ''
    ORDER BY P_Inner.Id, TagAlias_Inner.TagName -- Ensures a deterministic "first" tag is picked
) AS PrimaryTagIdentification ON P.Id = PrimaryTagIdentification.PostId
LEFT JOIN TagPopularityAndQuality AS TPQ_Main ON PrimaryTagIdentification.PrimaryTagName = TPQ_Main.TagName -- Join with overall tag statistics for the primary tag
WHERE
    U.Reputation >= 100 -- Filter for more established users
    AND P.PostTypeId IS NOT NULL -- Only consider actual posts
    AND P.CreationDate BETWEEN '2020-01-01 00:00:00' AND '2023-12-31 23:59:59' -- Specific time window for posts
    AND (P.ViewCount > 500 OR P.Score > 10) -- Filter for more viewed or highly-rated posts
    AND U.Location IS NOT NULL -- Filter for users with a specified location
ORDER BY
    UAS.Reputation DESC,
    UAS.TotalPostsOwned DESC,
    P.CreationDate DESC,
    PostActualUpvoteCount DESC
LIMIT 1000;
