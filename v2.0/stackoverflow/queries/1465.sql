-- {"query": "1465.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3010}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(COALESCE(P.Score,0)) AS TotalPostScoreOwned,
        AVG(COALESCE(P.ViewCount, 0)) AS AvgPostViewCount,
        MAX(P.LastActivityDate) AS LastPostActivity,
        (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.LastAccessDate))) / (60 * 60 * 24) AS DaysSinceLastAccess,
        (SELECT COUNT(DISTINCT Q.Id)
         FROM Posts Q
         WHERE Q.OwnerUserId = U.Id
           AND Q.PostTypeId = 1
           AND Q.Tags LIKE '%<sql>%'
        ) AS SqlTaggedQuestionsCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
    HAVING U.Reputation >= 5000
),
PostHistoryAndCommentEvents AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.UserId AS EventUserId,
        'PostHistory' AS EventSource,
        NULLIF(PH.Comment, '') AS EventComment,
        PH.Text AS EventText
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 16, 33)
    UNION ALL
    SELECT
        C.PostId,
        C.CreationDate AS EventDate,
        NULL AS PostHistoryTypeId,
        'Comment' AS HistoryTypeName,
        C.UserId AS EventUserId,
        'Comment' AS EventSource,
        NULLIF(C.Text, '') AS EventComment,
        NULL AS EventText
    FROM Comments C
    WHERE C.Score > 5
),
AggregatedPostEvents AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.Title,
        P.Tags,
        P.ParentId,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.LastEditDate,
        SUM(CASE WHEN PHE.HistoryTypeName LIKE 'Edit%' THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PHE.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN PHE.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN PHE.HistoryTypeName = 'Comment' THEN 1 ELSE 0 END) AS HighScoreCommentCount,
        MAX(CASE WHEN PHE.HistoryTypeName LIKE 'Edit%' THEN PHE.EventDate ELSE NULL END) AS LastEditHistoryDate
    FROM Posts P
    LEFT JOIN PostHistoryAndCommentEvents PHE ON P.Id = PHE.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.Title, P.Tags, P.ParentId, P.AcceptedAnswerId, P.ClosedDate, P.LastEditDate
),
TopUsersByTagEngagement AS (
    WITH RECURSIVE tag_split AS (
        SELECT
            P.Id AS post_id,
            P.OwnerUserId AS user_id,
            TRIM(
                CASE
                    WHEN POSITION('><' IN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2))) = 0
                        THEN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2))
                    ELSE SUBSTRING(P.Tags FROM 2 FOR POSITION('><' IN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2)))-1)
                END
            ) AS tag_text,
            CASE
                WHEN POSITION('><' IN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2))) = 0 THEN ''
                ELSE SUBSTRING(SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2)) FROM POSITION('><' IN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags)-2)))+2)
            END AS rest
        FROM Posts P
        WHERE P.Tags IS NOT NULL AND P.Tags <> '' AND P.PostTypeId = 1
        UNION ALL
        SELECT
            post_id,
            user_id,
            TRIM(CASE
                WHEN POSITION('><' IN rest) = 0 THEN rest
                ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1)
            END) AS tag_text,
            CASE
                WHEN POSITION('><' IN rest) = 0 THEN ''
                ELSE SUBSTRING(rest FROM POSITION('><' IN rest)+2)
            END AS rest
        FROM tag_split
        WHERE rest <> ''
    )
    SELECT
        user_id AS UserId,
        tag_text AS TagName,
        COUNT(DISTINCT post_id) AS PostsInTag,
        SUM((SELECT COALESCE(SUM(p2.Score),0) FROM Posts p2 WHERE p2.Id = tag_split.post_id)) AS ScoreInTag
    FROM tag_split
    GROUP BY user_id, tag_text
    HAVING COUNT(DISTINCT post_id) > 5
),
UserBadgeData AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS LatestGoldBadgeDate,
        MIN(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS EarliestGoldBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
VoteAnalysis AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesReceived,
        SUM(CASE WHEN V.VoteTypeId IN (4, 12) THEN 1 ELSE 0 END) AS FlagVotesReceived
    FROM Votes V
    GROUP BY V.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.QuestionsWithAcceptedAnswers,
    UAS.TotalPostScoreOwned,
    UAS.AvgPostViewCount,
    UAS.SqlTaggedQuestionsCount,
    UAS.DaysSinceLastAccess,
    COALESCE(UBD.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(UBD.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UBD.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UBD.BronzeBadges, 0) AS UserBronzeBadges,
    UBD.LatestGoldBadgeDate,
    COUNT(DISTINCT APE.PostId) AS ActivePostsCount,
    SUM(APE.EditCount) AS TotalPostEdits,
    SUM(APE.CloseCount) AS TotalPostCloseEvents,
    SUM(APE.ReopenCount) AS TotalPostReopenEvents,
    AVG(APE.HighScoreCommentCount) AS AvgHighScoreCommentsPerPost,
    STRING_AGG(DISTINCT TUTE.TagName || ' (' || TUTE.PostsInTag || ' posts, ' || TUTE.ScoreInTag || ' score)', '; ') AS TopTagEngagement,
    RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.UserTotalUpVotes DESC) AS OverallReputationRank,
    NTH_VALUE(UAS.DisplayName, 2) OVER (ORDER BY UAS.Reputation DESC) AS SecondHighestRepUser,
    (UAS.Reputation * 0.1
     + UAS.TotalQuestionsOwned * 0.5
     + UAS.TotalAnswersOwned * 0.8
     + UAS.TotalPostScoreOwned * 0.05
     + COALESCE(UBD.GoldBadges, 0) * 5
     - UAS.DaysSinceLastAccess * 0.01
     - UAS.UserTotalDownVotes * 0.1
    ) AS ContributorScore,
    UPPER(SUBSTRING(COALESCE(U.Location, 'UNKNOWN') FROM 1 FOR LEAST(10, LENGTH(COALESCE(U.Location, 'UNKNOWN'))))) ||
    CASE WHEN LENGTH(COALESCE(U.Location, 'UNKNOWN')) > 10 THEN '...' ELSE '' END ||
    ' [' || REPLACE(LOWER(COALESCE(U.Location, 'UNKNOWN')), ' ', '_') || ']' AS FormattedLocationInfo,
    COALESCE(SUM(VA.UpVotesReceived) * 1.0 / NULLIF(SUM(VA.DownVotesReceived), 0), SUM(VA.UpVotesReceived) * 1.0, 0) AS OverallPostVoteRatio,
    COUNT(CASE WHEN APE.ClosedDate IS NOT NULL AND APE.PostCreationDate IS NOT NULL
                AND APE.ClosedDate < (APE.PostCreationDate + INTERVAL '7 days') THEN APE.PostId END) AS QuickClosePostCount,
    EXISTS (
        SELECT 1
        FROM Posts P_INNER
        WHERE P_INNER.OwnerUserId = UAS.UserId
          AND P_INNER.PostTypeId = 1
          AND P_INNER.ViewCount > 100000
          AND P_INNER.Tags LIKE '%<java>%'
          AND P_INNER.AcceptedAnswerId IS NOT NULL
    ) AS HasHighlyViewedJavaQuestionWithAcceptedAnswer
FROM UserActivitySummary UAS
LEFT JOIN Users U ON UAS.UserId = U.Id
LEFT JOIN AggregatedPostEvents APE ON UAS.UserId = APE.OwnerUserId
LEFT JOIN UserBadgeData UBD ON UAS.UserId = UBD.UserId
LEFT JOIN VoteAnalysis VA ON APE.PostId = VA.PostId
LEFT JOIN (
    SELECT
        UserId,
        TagName,
        PostsInTag,
        ScoreInTag,
        ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY ScoreInTag DESC, PostsInTag DESC) AS RN
    FROM TopUsersByTagEngagement
) TUTE ON UAS.UserId = TUTE.UserId
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.TotalPostsOwned, UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned, UAS.QuestionsWithAcceptedAnswers, UAS.TotalPostScoreOwned,
    UAS.AvgPostViewCount, UAS.SqlTaggedQuestionsCount, UAS.DaysSinceLastAccess,
    UBD.TotalBadges, UBD.GoldBadges, UBD.SilverBadges, UBD.BronzeBadges, UBD.LatestGoldBadgeDate,
    U.Location,
    UAS.UserTotalUpVotes, UAS.UserTotalDownVotes,
    UAS.UserId, UAS.DisplayName, UAS.Reputation,
    EXISTS (
        SELECT 1
        FROM Posts P_INNER
        WHERE P_INNER.OwnerUserId = UAS.UserId
          AND P_INNER.PostTypeId = 1
          AND P_INNER.ViewCount > 100000
          AND P_INNER.Tags LIKE '%<java>%'
          AND P_INNER.AcceptedAnswerId IS NOT NULL
    )
HAVING
    UAS.TotalPostsOwned > 10
    AND COALESCE(UBD.GoldBadges, 0) >= 1
ORDER BY
    ContributorScore DESC, OverallReputationRank
LIMIT 100;