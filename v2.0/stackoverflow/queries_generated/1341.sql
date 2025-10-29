-- {"query": "1341.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1658} 

WITH UserPostDetails AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.AboutMe,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(P.Score) AS TotalPostScoreReceived,
        SUM(P.ViewCount) AS TotalQuestionViewCount,
        SUM(P.FavoriteCount) AS TotalFavoriteCounts,
        COALESCE(AVG(LENGTH(P.Body)), 0) AS AvgPostBodyLength,
        -- Complex string manipulation: aggregate distinct tags from questions
        STRING_AGG(
            DISTINCT SUBSTRING(
                TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))),
                1, 35
            ), ';' ORDER BY SUBSTRING(
                TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))),
                1, 35
            )
        ) FILTER (WHERE P.Tags IS NOT NULL AND P.Tags != '$$' AND P.PostTypeId = 1) AS DistinctTagsUsed, -- Filter for questions and non-empty tags
        -- Correlated subquery: find the title of the user's most recent post
        (SELECT Title FROM Posts WHERE OwnerUserId = U.Id ORDER BY CreationDate DESC LIMIT 1) AS MostRecentPostTitle,
        -- Correlated subquery: find the creation date of the user's most recent post
        (SELECT CreationDate FROM Posts WHERE OwnerUserId = U.Id ORDER BY CreationDate DESC LIMIT 1) AS MostRecentPostDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe, U.Views, U.UpVotesGiven, U.DownVotesGiven
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM
        Badges B
    GROUP BY
        B.UserId
),
UserCommentMetrics AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalCommentsMade,
        COALESCE(AVG(C.Score), 0) AS AvgCommentScore,
        SUM(LENGTH(C.Text)) AS TotalCommentChars
    FROM
        Comments C
    WHERE
        C.UserId IS NOT NULL
    GROUP BY
        C.UserId
),
PostLifeCycleMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate AS PostLastEditDate,
        P.ClosedDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents, -- 4:Edit Title, 5:Edit Body, 6:Edit Tags
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryEvents, -- 10:Post Closed
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenHistoryEvents, -- 11:Post Reopened
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastActualEditDateFromHistory,
        -- String expression and NULL logic: Extract CloseReasonId from comment field if present and matches pattern
        STRING_AGG(DISTINCT
            SUBSTRING(PH.Comment, POSITION('CloseReasonId=' IN PH.Comment) + LENGTH('CloseReasonId='))
            , ',') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment LIKE 'CloseReasonId=%') AS AllCloseReasonIds
    FROM
        Posts P
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.ClosedDate
),
UserVoteInfluence AS (
    SELECT
        PH.UserId AS VoterId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS UserCloseVotesCast,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS UserReopenVotesCast,
        COUNT(DISTINCT PH.PostId) AS DistinctPostsVotedOnForModeration,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) * 10 + SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) * 5 AS ModerationActivityScore
    FROM
        PostHistory PH
    WHERE
        PH.UserId IS NOT NULL AND PH.PostHistoryTypeId IN (10, 11)
    GROUP BY
        PH.UserId
),
AvgOwnedPostMetrics AS (
    SELECT
        PLCM.OwnerUserId AS UserId,
        COALESCE(AVG(PLCM.TotalEditEvents), 0) AS AvgEditsPerOwnedPost,
        COALESCE(AVG(PLCM.DistinctEditors), 0) AS AvgDistinctEditorsPerOwnedPost,
        COALESCE(SUM(PLCM.CloseHistoryEvents), 0) AS OwnedPostsClosedEvents,
        COALESCE(SUM(PLCM.ReopenHistoryEvents), 0) AS OwnedPostsReopenedEvents,
        -- Calculation: Average days from post creation to its last recorded edit in history
        COALESCE(AVG(EXTRACT(EPOCH FROM (PLCM.LastActualEditDateFromHistory - PLCM.PostCreationDate)) / (60 * 60 * 24)), 0) AS AvgDaysToLastEdit
    FROM
        PostLifeCycleMetrics PLCM
    WHERE
        PLCM.OwnerUserId IS NOT NULL
    GROUP BY
        PLCM.OwnerUserId
),
OverallInfluencers AS (
    SELECT
        'Overall Influencer' AS UserSegment,
        U.Id AS UserId,
        UPD.DisplayName,
        UPD.Reputation,
        UPD.UserCreationDate,
        UPD.LastAccessDate,
        EXTRACT(EPOCH FROM (NOW() - UPD.UserCreationDate)) / (6