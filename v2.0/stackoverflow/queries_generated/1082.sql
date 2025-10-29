-- {"query": "1082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2275} 

WITH UserCoreStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Calculate reputation growth rate, handle division by zero for new users
        CASE
            WHEN (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400.0) > 0
            THEN U.Reputation / (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400.0)
            ELSE 0.0
        END AS ReputationPerDay
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryCreationDate,
        PH.UserId AS HistoryUserId,
        PH.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS HistoryRankAsc,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS PreviousHistoryDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalEditsPerPost
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 16) -- Initial, Edit, Close/Reopen, Delete/Undelete, Community Owned events
),
AggregatedPostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COALESCE(MAX(PHT.TotalEditsPerPost), 0) AS ActualEditCount,
        MAX(PHT.HistoryCreationDate) AS LatestPostActivity,
        MIN(PHT.HistoryCreationDate) AS EarliestPostActivity,
        -- Calculate the "age" of the post based on last activity vs first activity
        EXTRACT(EPOCH FROM (COALESCE(MAX(PHT.HistoryCreationDate), P.CreationDate) - P.CreationDate)) / 86400.0 AS PostLifespanDays,
        (
            SELECT PH_initial.HistoryText
            FROM PostHistoryTimeline PH_initial
            WHERE PH_initial.PostId = P.Id
              AND PH_initial.PostHistoryTypeId = 2 -- Initial Body
            ORDER BY PH_initial.HistoryCreationDate ASC
            LIMIT 1
        ) AS InitialBodyContent, -- Correlated Subquery 1: Fetches the very first body content
        STRING_AGG(DISTINCT LOWER(TRIM(UNNEST_TAG.tag)), ', ') FILTER (WHERE UNNEST_TAG.tag IS NOT NULL AND LENGTH(TRIM(UNNEST_TAG.tag)) > 0) AS ParsedTagList
    FROM Posts P
    LEFT JOIN PostHistoryTimeline PHT ON P.Id = PHT.PostId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag
    ) AS UNNEST_TAG ON P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.CommunityOwnedDate
),
CommentSentimentAnalysis AS (
    SELECT
        C.PostId,
        C.UserId AS CommentOwnerId,
        C.CreationDate AS CommentCreationDate,
        C.Text AS CommentContent,
        C.Score AS CommentScore,
        COUNT(C.Id) OVER (PARTITION BY C.PostId) AS TotalCommentsOnThisPost,
        AVG(C.Score) OVER (PARTITION BY C.PostId) AS AvgCommentScoreOnThisPost,
        CASE
            WHEN LOWER(C.Text) LIKE '%great%' OR LOWER(C.Text) LIKE '%helpful%' OR LOWER(C.Text) LIKE '%thanks%' THEN 'Positive'
            WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%wrong%' THEN 'Negative'
            ELSE 'Neutral'
        END AS CommentSentiment,
        ROW_NUMBER() OVER (PARTITION BY C.PostId ORDER BY C.CreationDate DESC) AS RnkLatestComment
    FROM Comments C
),
AggregatedUserBadgeStatus AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS UserTotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadgeCount,
        MAX(B.Date) AS LatestBadgeAwardDate,
        MIN(B.Date) AS FirstBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
PostVoteAggregates AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountFromVotes -- From old Favorites, feature removed after October 2022
    FROM Votes V
    WHERE V.VoteTypeId IN (2, 3, 5)
    GROUP BY V.PostId
),
BaseQueryData AS (
    SELECT
        COALESCE(U_base.Id, AUB.UserId, P_joined.OwnerUserId, C_joined.UserId) AS UnifiedUserId, -- Ensure all possible user sources are covered
        UCS.DisplayName,
        UCS.Reputation,
        UCS.ReputationPerDay,
        UCS.TotalPostsOwned,
        UCS.TotalCommentsMade,
        AUB.UserTotalBadges,
        AUB.GoldBadgeCount,
        AUB.SilverBadgeCount,
        AUB.BronzeBadgeCount,
        AUB.LatestBadgeAwardDate,
        APA.PostId,
        APA.PostTypeId,
        PT.Name AS PostTypeName,
        APA.Title AS PostTitle,
        APA.PostCreationDate,
        APA.PostScore,
        APA.ViewCount AS PostViewCount,
        APA.ActualEditCount,
        APA.ParsedTagList,
        APA.InitialBodyContent, -- Correlated Subquery 1 result
        CS.CommentContent AS LatestCommentText,
        CS.CommentSentiment AS LatestCommentSentiment,
        PL.RelatedPostId AS LinkedRelatedPostId,
        LT.Name AS LinkTypeName,
        PVA.UpvoteCount,
        PVA.DownvoteCount,
        PVA.FavoriteCountFromVotes AS OldFavoriteCount,
        -- Complex calculated fields and conditional logic
        CASE
            WHEN APA.ActualEditCount > 5 AND APA.PostScore < 0 THEN 'Troubled_HighlyEdited'
            WHEN APA.PostScore >= 100 AND UCS.TotalPostsOwned > 50 THEN 'HighImpact_Prolific'
            WHEN UCS.Reputation > 10000 AND AUB.GoldBadgeCount > 0 AND APA.PostTypeId = 1 THEN 'Veteran_InfluentialQuestioner'
            WHEN APA.ClosedDate IS NOT NULL AND PHT_Closed.HistoryUserId IS NOT NULL AND PHT_Closed.HistoryUserId != APA.OwnerUserId THEN 'ClosedByOthers'
            ELSE 'RegularContributor'
        END AS UserPostCategory,
        -- Correlated Subquery 2: Check if any post of this user has a specific tag AND was edited by another user
        (
            SELECT EXISTS (
                SELECT 1
                FROM AggregatedPostActivity APA2
                JOIN PostHistoryTimeline PHT_editor ON APA2.PostId = PHT_editor.PostId
                WHERE APA2.OwnerUserId = COALESCE(U_base.Id, AUB.UserId, P_joined.OwnerUserId)
                  AND PHT_editor.PostHistoryTypeId IN (4,5,6) -- Edit event
                  AND PHT_editor.HistoryUserId IS NOT NULL
                  AND PHT_editor.HistoryUserId != COALESCE(U_base.Id, AUB.UserId, P_joined.OwnerUserId) -- Edited by someone else
                  AND APA2.ParsedTagList LIKE '%performance%'
                LIMIT 1
            )
        ) AS HasPerformanceTagEditedByOthers,