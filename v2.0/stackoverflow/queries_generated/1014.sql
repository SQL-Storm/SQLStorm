-- {"query": "1014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3448} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT Q_Accepted.Id) AS AcceptedAnswersCount, -- Count questions where this user's answer was accepted
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(AVG(P.Score), 0) AS AvgOwnedPostScore,
        MAX(P.CreationDate) AS LastOwnedPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts AS Q_Accepted ON P.Id = Q_Accepted.AcceptedAnswerId AND Q_Accepted.PostTypeId = 1
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS PostBaseScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AnswerCount,
        COUNT(DISTINCT V_Up.Id) AS UpVotesReceived,
        COUNT(DISTINCT V_Down.Id) AS DownVotesReceived,
        SUM(CASE WHEN V_Bounty.VoteTypeId = 8 THEN V_Bounty.BountyAmount ELSE 0 END) AS BountyStartedAmount,
        SUM(CASE WHEN V_Bounty.VoteTypeId = 9 THEN V_Bounty.BountyAmount ELSE 0 END) AS BountyClosedAmount,
        SUM(CASE V_All.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS NetExplicitVoteScore
    FROM Posts AS P
    LEFT JOIN Votes AS V_Up ON P.Id = V_Up.PostId AND V_Up.VoteTypeId = 2
    LEFT JOIN Votes AS V_Down ON P.Id = V_Down.PostId AND V_Down.VoteTypeId = 3
    LEFT JOIN Votes AS V_Bounty ON P.Id = V_Bounty.PostId AND V_Bounty.VoteTypeId IN (8,9)
    LEFT JOIN Votes AS V_All ON P.Id = V_All.PostId AND V_All.VoteTypeId IN (2,3)
    GROUP BY P.Id, P.PostTypeId, P.Score, P.ViewCount, P.CommentCount, P.FavoriteCount, P.AnswerCount
),
PostTagMap AS (
    SELECT
        P.Id AS PostId,
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND P.Tags != '><' AND P.PostTypeId = 1
),
TagUsageMetrics AS (
    SELECT
        PTM.TagName,
        COUNT(DISTINCT PTM.PostId) AS TaggedPostCount,
        COALESCE(AVG(P.Score), 0) AS AvgScoreForTagPosts,
        MAX(P.CreationDate) AS LastTagUsageDate,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT PTM.PostId) DESC, COALESCE(AVG(P.Score), 0) DESC) AS TagPopularityRank
    FROM PostTagMap AS PTM
    JOIN Posts AS P ON PTM.PostId = P.Id
    GROUP BY PTM.TagName
),
HistoricalPostEdits AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 7) THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (6, 9) THEN 1 ELSE 0 END) AS TagEdits,
        MAX(PH.CreationDate) AS LastEditActivityDate,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN LENGTH(PH.Text) ELSE 0 END) AS MaxBodyLengthPostEdit
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
ClosedPostAnalysisRaw AS (
    SELECT
        PH.PostId,
        CR.Name AS ActualCloseReasonName,
        PH.CreationDate AS ClosureDate,
        PH.UserId AS ClosingUserId,
        PH.Comment AS CloseReasonComment,
        PH.Text AS CloseVotersJson,
        (SELECT COUNT(DISTINCT PH_Reopen.PostId) FROM PostHistory PH_Reopen
         WHERE PH_Reopen.PostId = PH.PostId
           AND PH_Reopen.PostHistoryTypeId = 11 -- Post Reopened
           AND PH_Reopen.CreationDate > PH.CreationDate
        ) AS ReopenEventsAfterClose
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CR ON CAST(SUBSTRING(PH.Comment FROM '[0-9]+') AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId = 10 -- Post Closed
),
PostClosureSummary AS (
    SELECT
        PostId,
        MIN(ClosureDate) AS FirstClosureDate,
        MAX(ClosureDate) AS LastClosureDate,
        COUNT(*) AS TotalClosureEvents,
        STRING_AGG(DISTINCT ActualCloseReasonName, '; ') AS AllCloseReasons,
        COALESCE(SUM(ReopenEventsAfterClose), 0) AS TotalReopenEvents,
        (SELECT COUNT(DISTINCT json_value) FROM jsonb_array_elements_text(COALESCE(MAX(CASE WHEN CloseVotersJson LIKE '[%]' THEN CloseVotersJson END)::jsonb, '[]'::jsonb)) AS json_value) AS UniqueCloseVotersCount
    FROM ClosedPostAnalysisRaw
    GROUP BY PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT B.Name, ', ') AS AllBadgeNames,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges AS B
    GROUP BY B.UserId
),
TopQuestionTags AS (
    SELECT
        TagName
    FROM TagUsageMetrics
    WHERE TagPopularityRank <= 10
),
RecentCommentActivity AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS RecentCommentCount,
        COUNT(DISTINCT C.UserId) AS RecentUniqueCommenters,
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Comments AS C
    WHERE C.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY C.PostId
),
QuestionAnswerChain AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY Q.Id ORDER BY A.CreationDate) AS AnswerSequence,
        CASE WHEN A.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM Posts AS Q
    JOIN Posts AS A ON Q.Id = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.UserViews,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.AcceptedAnswersCount,
    UAS.TotalComments,
    UAS.AvgOwnedPostScore,
    UBS.TotalBadges,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.LastBadgeAwardDate,
    TP.Id AS PostId,
    TP.PostTypeId,
    TP.CreationDate AS PostCreationDate,
    TP.Title AS PostTitle,
    TP.Score AS PostScore,
    TP.ViewCount AS PostViewCount,
    TP.CommentCount AS PostCommentCount,
    TP.FavoriteCount AS PostFavoriteCount,
    TP.AnswerCount AS PostAnswerCount,
    PEM.UpVotesReceived,
    PEM.DownVotesReceived,
    PEM.NetExplicitVoteScore,
    HPE.TotalHistoryEntries,
    HPE.LastEditActivityDate,
    HPE.UniqueEditors,
    PCS.TotalClosureEvents,
    PCS.FirstClosureDate,
    PCS.AllCloseReasons,
    PCS.UniqueCloseVotersCount,
    RCA.RecentCommentCount,
    RCA.LatestCommentDate,
    STRING_AGG(DISTINCT PTM_Q.TagName, ', ') FILTER (WHERE PTM_Q.TagName IS NOT NULL) AS QuestionTags,
    SUM(CASE WHEN PTM_Q.TagName IN (SELECT TagName FROM TopQuestionTags) THEN 1 ELSE 0 END) AS HotTagQuestionCount,
    ROW_NUMBER() OVER (PARTITION BY UAS.UserCreationDate::DATE ORDER BY UAS.Reputation DESC, UAS.TotalPosts DESC) AS UserDailyRankByReputation,
    NTILE(10) OVER (ORDER BY TP.Score DESC, TP.ViewCount DESC, TP.FavoriteCount DESC) AS PostEngagementDecile,
    LAG(TP.CreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY UAS.UserId ORDER BY TP.CreationDate) AS PrevPostCreationDate,
    (TP.Score * 0.5 + PEM.NetExplicitVoteScore * 0.3 + (COALESCE(TP.FavoriteCount, 0) * 2) + COALESCE(TP.AnswerCount, 0) * 1.5) AS WeightedPostEngagement,
    (EXTRACT(EPOCH FROM (NOW() - TP.CreationDate)) / (60 * 60 * 24 * 365.25)) AS PostAgeYears,
    COALESCE(TP.AcceptedAnswerId, -1) AS AcceptedAnswerStatus,
    NULLIF(LENGTH(TP.Body), 0) AS BodyLength,
    CASE WHEN EXISTS (SELECT 1 FROM Badges B_Gold WHERE B_Gold.UserId = UAS.UserId AND B_Gold.Class = 1) THEN TRUE ELSE FALSE END AS HasGoldBadge,
    (SELECT COALESCE(AVG(QA.AnswerScore), 0)
     FROM QuestionAnswerChain AS QA
     WHERE QA.QuestionId = TP.Id
       AND TP.PostTypeId = 1
    ) AS AvgAnswerScoreForQuestion,
    PL.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeName,
    (CASE WHEN TP.Body ILIKE '%performance%' OR TP.Body ILIKE '%optimization%' OR TP.Title ILIKE '%query speed%' THEN TRUE ELSE FALSE END) AS ContainsPerformanceKeyword,
    (UAS.Reputation * 0.1 / (NULLIF(UAS.TotalPosts + UAS.TotalComments + UAS.AcceptedAnswersCount, 0)::NUMERIC)) +
    (COALESCE(TP.Score, 0) + COALESCE(PEM.NetExplicitVoteScore, 0)) AS UserPostInfluenceMetric
FROM UserActivitySummary AS UAS
LEFT JOIN UserBadgeSummary AS UBS ON UAS.UserId = UBS.UserId
LEFT JOIN Posts AS TP ON UAS.UserId = TP.OwnerUserId
LEFT JOIN PostEngagementMetrics AS PEM ON TP.Id = PEM.PostId
LEFT JOIN HistoricalPostEdits AS HPE ON TP.Id = HPE.PostId
LEFT JOIN PostClosureSummary AS PCS ON TP.Id = PCS.PostId
LEFT JOIN RecentCommentActivity AS RCA ON TP.Id = RCA.PostId
LEFT JOIN PostTagMap AS PTM_Q ON TP.Id = PTM_Q.PostId AND TP.PostTypeId = 1
LEFT JOIN PostLinks AS PL ON TP.Id = PL.PostId
LEFT JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
WHERE UAS.Reputation > 10000
  AND TP.PostTypeId IN (1, 2)
  AND TP.CreationDate >= '2020-01-01'
  AND (TP.ViewCount > 500 OR COALESCE(TP.FavoriteCount, 0) > 10)
  AND NOT EXISTS (
      SELECT 1 FROM Comments C_spam
      WHERE C_spam.PostId = TP.Id AND C_spam.Text ILIKE '%spam%'
  )
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.UserViews, UAS.TotalPosts,
    UAS.TotalQuestions, UAS.TotalAnswers, UAS.AcceptedAnswersCount, UAS.TotalComments,
    UAS.AvgOwnedPostScore, UBS.TotalBadges, UBS.GoldBadges, UBS.SilverBadges, UBS.LastBadgeAwardDate,
    TP.Id, TP.PostTypeId, TP.CreationDate, TP.Title, TP.Score, TP.ViewCount, TP.CommentCount,
    TP.FavoriteCount, TP.AnswerCount, PEM.UpVotesReceived, PEM.DownVotesReceived, PEM.NetExplicitVoteScore,
    HPE.TotalHistoryEntries, HPE.LastEditActivityDate, HPE.UniqueEditors, PCS.TotalClosureEvents,
    PCS.FirstClosureDate, PCS.AllCloseReasons, PCS.UniqueCloseVotersCount, RCA.RecentCommentCount,
    RCA.LatestCommentDate, PL.RelatedPostId, LT.Name
HAVING COUNT(PTM_Q.TagName) FILTER (WHERE PTM_Q.TagName IN (SELECT TagName FROM TopQuestionTags)) >= 1
ORDER BY UAS.Reputation DESC, WeightedPostEngagement DESC
LIMIT 1000;
