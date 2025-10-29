-- {"query": "1633.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2580}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerQuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts PARENT_POST WHERE PARENT_POST.Id = P.ParentId AND PARENT_POST.AcceptedAnswerId = P.Id) THEN 1 ELSE 0 END) AS AnswersAcceptedByOthersCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.UpVotes, U.DownVotes, U.Views, U.CreationDate
),
PostAnalytics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.LastEditDate,
        COALESCE(P.Title, 'Untitled Post') AS PostTitle,
        LENGTH(P.Body) AS BodyLength,
        CASE
            WHEN P.Tags IS NOT NULL THEN (
                SELECT MIN(value)
                FROM UNNEST(string_to_array(substring(P.Tags FROM 2 FOR char_length(P.Tags)-2), '><')) AS value
                WHERE value <> ''
            )
            ELSE NULL
        END AS PrimaryTag,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditRevisionCount,
        (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryTimestamp
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
),
BadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
PostLinkAnalysis AS (
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE NULL END) AS LinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE NULL END) AS DuplicateOfCount
    FROM PostLinks PL
    GROUP BY PL.PostId
),
VoteTypeCounts AS (
    SELECT
        V.PostId,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVoteCount,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVoteCount,
        COUNT(CASE WHEN V.VoteTypeId = 4 THEN 1 ELSE NULL END) AS OffensiveVoteCount
    FROM Votes V
    GROUP BY V.PostId
)
SELECT
    UE.UserId,
    U.DisplayName,
    UE.Reputation,
    UE.UpVotes AS UserTotalUpVotesGiven,
    UE.DownVotes AS UserTotalDownVotesGiven,
    UE.UserProfileViews,
    UE.TotalPostsOwned,
    UE.QuestionCount,
    UE.AnswerCount,
    COALESCE(BS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(BS.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS UserBronzeBadges,
    PA.PostId,
    PT.Name AS PostTypeName,
    PA.PostTitle,
    PA.Score AS PostCurrentScore,
    PA.ViewCount AS PostTotalViewCount,
    PA.FavoriteCount AS PostBookmarkCount,
    PA.AnswerCount AS PostTotalAnswerCount,
    PA.CommentCount AS PostTotalCommentCount,
    VT.UpVoteCount AS PostUpVotesReceived,
    VT.DownVoteCount AS PostDownVotesReceived,
    VT.OffensiveVoteCount AS PostOffensiveVotesReceived,
    PA.PrimaryTag,
    PA.BodyLength AS PostBodyCharacterLength,
    PLA.LinkedPostsCount,
    PLA.DuplicateOfCount,
    PA.EditRevisionCount,
    EXTRACT(EPOCH FROM (PA.LastActivityDate - PA.PostCreationDate)) / 3600 AS HoursActiveSinceCreation,
    COALESCE(CLT.Name, 'N/A') AS CloseReasonName,
    CASE
        WHEN PA.PostTypeId = 1 AND PA.AcceptedAnswerId IS NOT NULL THEN 'Accepted_Answered'
        WHEN PA.PostTypeId = 1 AND PA.ClosedDate IS NOT NULL THEN 'Closed_Question'
        WHEN PA.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts P_PARENT WHERE P_PARENT.Id = PA.ParentId AND P_PARENT.AcceptedAnswerId = PA.PostId) THEN 'Accepted_Answer'
        ELSE 'Open_Active'
    END AS DetailedPostStatus,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY PA.Score DESC, PA.ViewCount DESC) AS RankOfPostByUserActivity,
    NTILE(5) OVER (ORDER BY UE.Reputation DESC, UE.UpVotes DESC, UE.TotalPostsOwned DESC) AS UserEngagementTier,
    AVG(PA.Score) OVER (PARTITION BY PA.PostTypeId ORDER BY PA.PostCreationDate ROWS BETWEEN 20 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreForType,
    LAG(PA.LastEditHistoryTimestamp, 1, PA.PostCreationDate) OVER (PARTITION BY UE.UserId, PA.PostId ORDER BY PA.LastEditHistoryTimestamp) AS PreviousEditTimestamp,
    CASE WHEN PA.Score = 0 THEN NULL ELSE CAST(NULLIF(PA.ViewCount, 0) AS numeric) / CAST(NULLIF(PA.Score, 0) AS numeric) END AS ViewScoreRatio,
    UE.AcceptedAnswerQuestionCount,
    UE.AnswersAcceptedByOthersCount,
    (UE.UpVotes + UE.DownVotes) AS UserTotalVotesCast,
    (SELECT
        CASE WHEN COUNT(P_RECENT.Id) > 0 THEN TRUE ELSE FALSE END
     FROM Posts P_RECENT
     WHERE P_RECENT.OwnerUserId = U.Id
       AND P_RECENT.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '60 days')
       AND P_RECENT.PostTypeId IN (1, 2)
    ) AS HasRecentSignificantPosts,
    (SELECT COALESCE(MAX(C_SCORE.Score), 0)
     FROM Comments C_SCORE
     WHERE C_SCORE.PostId = PA.PostId AND C_SCORE.Score >= 5
    ) AS MaxHighScoreCommentOnPost,
    (SELECT STRING_AGG(T.TagName, '; ')
     FROM Tags T
     WHERE T.TagName LIKE '%' || PA.PrimaryTag || '%'
       AND T.Count > 500
       AND T.Id <> (SELECT Id FROM Tags WHERE TagName = PA.PrimaryTag)
    ) AS RelatedPopularTagsString
FROM Users U
INNER JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN PostAnalytics PA ON U.Id = PA.OwnerUserId
LEFT JOIN PostTypes PT ON PA.PostTypeId = PT.Id
LEFT JOIN BadgeSummary BS ON U.Id = BS.UserId
LEFT JOIN PostLinkAnalysis PLA ON PA.PostId = PLA.PostId
LEFT JOIN VoteTypeCounts VT ON PA.PostId = VT.PostId
LEFT JOIN (
    SELECT DISTINCT ON (PostId) PostId, Comment
    FROM PostHistory
    WHERE PostHistoryTypeId = 10 AND Comment IS NOT NULL
    ORDER BY PostId, CreationDate DESC
) PH_CLOSE ON PA.PostId = PH_CLOSE.PostId
LEFT JOIN CloseReasonTypes CLT ON CAST(PH_CLOSE.Comment AS smallint) = CLT.Id
WHERE U.Reputation > 10000
  AND U.LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '180 days')
  AND (PA.PostId IS NULL OR (PA.Score > 10 AND PA.CommentCount >= 3 AND PA.BodyLength > 150))
  AND (UE.TotalPostsOwned > 0 OR UE.TotalCommentsMade > 5)
  AND UE.UserCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year')
ORDER BY UE.Reputation DESC, UserGoldBadges DESC, PostCurrentScore DESC, PA.PostCreationDate DESC
LIMIT 500;