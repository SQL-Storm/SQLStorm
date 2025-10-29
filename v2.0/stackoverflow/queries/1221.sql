-- {"query": "1221.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3168}
WITH UserEngagement AS (
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
        SUM(P.Score) AS TotalPostScore,
        AVG(LENGTH(COALESCE(CAST(P.ViewCount AS TEXT), '0'))) AS AvgPostViewCount,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LatestBadgeDate,
        RANK() OVER (ORDER BY U.Reputation DESC) AS UserReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS HasClosureOrReopenEvent,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MIN(PH.CreationDate) AS FirstEditDate,
        MAX(PH.CreationDate) AS LatestEditDate,
        AVG(LENGTH(COALESCE(PH.Text, ''))) AS AvgEditBodyLength
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY PH.PostId
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        AVG(LENGTH(COALESCE(C.Text, ''))) AS AvgCommentLength,
        COUNT(DISTINCT C.UserId) AS UniqueCommenters
    FROM Comments C
    GROUP BY C.PostId
),
PostVoteAnalysis AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived,
        SUM(CASE WHEN V.VoteTypeId IN (8, 9) THEN COALESCE(V.BountyAmount, 0) ELSE 0 END) AS TotalBountyAmount
    FROM Votes V
    WHERE V.VoteTypeId IN (1, 2, 3, 5, 8, 9, 10, 11, 12)
    GROUP BY V.PostId
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScoreForTag,
        AVG(p.ViewCount) AS AvgViewCountForTag,
        NTILE(5) OVER (ORDER BY COUNT(p.Id) DESC, AVG(p.Score) DESC) AS TagPopularityQuintile
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t
    WHERE p.Tags IS NOT NULL AND p.Tags <> '><' AND p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
),
QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.OwnerUserId AS QuestionOwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.Tags,
        COALESCE(pl.DuplicateCount, 0) AS DuplicateLinkCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_latest_question_by_user,
        LAG(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionViewCount,
        LEAD(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextQuestionViewCount
    FROM Posts p
    LEFT JOIN (
        SELECT RelatedPostId, COUNT(Id) AS DuplicateCount
        FROM PostLinks
        WHERE LinkTypeId = 3
        GROUP BY RelatedPostId
    ) pl ON p.Id = pl.RelatedPostId
    WHERE p.PostTypeId = 1
),
AnswerDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        p.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_best_answer
    FROM Posts p
    WHERE p.PostTypeId = 2
),
SpecialPostsFlag AS (
    SELECT p.Id AS PostId, 'High_Score_Question' AS SpecialReason
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 750
    UNION ALL
    SELECT p.Id AS PostId, 'Many_Edits_Answer' AS SpecialReason
    FROM Posts p
    JOIN (
        SELECT PostId, COUNT(Id) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY PostId
        HAVING COUNT(Id) > 15
    ) ph_edits ON p.Id = ph_edits.PostId
    WHERE p.PostTypeId = 2
)
SELECT
    QD.QuestionId,
    QD.QuestionTitle,
    QD.QuestionCreationDate,
    QD.QuestionScore,
    QD.QuestionViewCount,
    QD.AnswerCount,
    QD.FavoriteCount,
    UE.DisplayName AS QuestionOwnerDisplayName,
    UE.Reputation AS QuestionOwnerReputation,
    UE.UserReputationRank,
    PEA.TotalEdits AS PostEditCount,
    PEA.UniqueEditors AS PostUniqueEditors,
    PCS.TotalComments AS PostCommentCount,
    PCS.TotalCommentScore AS PostTotalCommentScore,
    PVA.UpVotesReceived AS QuestionUpVotes,
    PVA.DownVotesReceived AS QuestionDownVotes,
    AD.AnswerId AS AcceptedAnswerId,
    AD.AnswerScore AS AcceptedAnswerScore,
    U_AD.DisplayName AS AcceptedAnswerOwnerDisplayName,
    TP.TagName AS TopContributingTag,
    TP.AvgScoreForTag AS TopTagAvgScore,
    TP.TagPopularityQuintile,
    COALESCE(SPF.SpecialReason, 'Normal') AS SpecialPostCategory,
    CASE
        WHEN QD.ClosedDate IS NOT NULL AND PEA.LastReopenedDate IS NOT NULL AND QD.ClosedDate < PEA.LastReopenedDate THEN 'Reopened'
        WHEN QD.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    CASE
        WHEN QD.AcceptedAnswerId IS NULL AND QD.AnswerCount > 0 AND QD.QuestionViewCount > 5000 THEN 'Unaccepted_HighViews'
        WHEN QD.AcceptedAnswerId IS NULL AND QD.AnswerCount = 0 AND QD.QuestionCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') THEN 'NoAnswer_LongUnresolved'
        WHEN QD.AnswerCount = 0 AND COALESCE(PEA.TotalEdits, 0) > 5 AND QD.QuestionScore > 10 THEN 'Unanswered_HighlyEdited_Positive'
        WHEN QD.QuestionScore > 200 AND QD.FavoriteCount > 20 AND COALESCE(PCS.TotalComments, 0) > 30 THEN 'HighEngagement_Viral'
        ELSE 'ModerateEngagement'
    END AS QuestionEngagementCategory,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = QD.QuestionId AND V.VoteTypeId = 5) AS UniqueFavoriters,
    (UE.Reputation > (SELECT AVG(U2.Reputation) FROM Users U2 WHERE EXTRACT(YEAR FROM U2.CreationDate) = EXTRACT(YEAR FROM UE.UserCreationDate) AND EXTRACT(MONTH FROM U2.CreationDate) = EXTRACT(MONTH FROM UE.UserCreationDate) AND U2.Id <> UE.UserId)) AS IsAboveMonthlyAvgReputation,
    QD.QuestionViewCount - COALESCE(QD.NextQuestionViewCount, 0) AS ViewCountDeltaToNextPost,
    QD.QuestionViewCount - COALESCE(QD.PrevQuestionViewCount, 0) AS ViewCountDeltaToPrevPost,
    UPPER(SUBSTR(QD.QuestionTitle, 1, 1)) AS FirstCharOfTitle,
    LENGTH(COALESCE(QD.QuestionTitle, '')) AS TitleLength,
    REPLACE(REPLACE(REPLACE(COALESCE(QD.Tags, '[no-tags]'), '>', ';'), '<', ''), ';;', ';') AS CleanedTagsString,
    COALESCE(QD.QuestionScore, 0) * (1 + COALESCE(QD.FavoriteCount, 0) * 0.15 + COALESCE(PCS.TotalComments, 0) * 0.07 + COALESCE(PEA.TotalEdits, 0) * 0.03) AS WeightedPopularityScore,
    (SELECT AVG(LENGTH(COALESCE(C.Text, ''))) FROM Comments C WHERE C.PostId = QD.QuestionId AND C.UserId = QD.QuestionOwnerUserId AND (C.Text LIKE '%question%')) AS AvgOwnerCommentLengthRelevant,
    QD.DuplicateLinkCount,
    CASE WHEN QD.rn_latest_question_by_user = 1 THEN TRUE ELSE FALSE END AS IsLatestQuestionByUser,
    RANK() OVER (ORDER BY QD.QuestionViewCount DESC, QD.QuestionScore DESC, COALESCE(COALESCE(QD.QuestionScore, 0) * (1 + COALESCE(QD.FavoriteCount, 0) * 0.15 + COALESCE(PCS.TotalComments, 0) * 0.07 + COALESCE(PEA.TotalEdits, 0) * 0.03), 0) DESC) AS GlobalEngagementRank,
    (SELECT MAX(u3.Reputation)
     FROM Users u3
     WHERE (u3.Location = CAST(UE.UserCreationDate AS TEXT) OR u3.Location = UE.DisplayName) IS FALSE
       AND u3.Location = UE.DisplayName
       AND u3.Reputation < UE.Reputation
       AND u3.Id <> UE.UserId
    ) AS NextLowerReputationInSameLocation
FROM QuestionDetails QD
INNER JOIN UserEngagement UE ON QD.QuestionOwnerUserId = UE.UserId
LEFT JOIN PostEditActivity PEA ON QD.QuestionId = PEA.PostId
LEFT JOIN PostCommentSummary PCS ON QD.QuestionId = PCS.PostId
LEFT JOIN PostVoteAnalysis PVA ON QD.QuestionId = PVA.PostId
LEFT JOIN SpecialPostsFlag SPF ON QD.QuestionId = SPF.PostId
LEFT JOIN AnswerDetails AD ON QD.AcceptedAnswerId = AD.AnswerId AND AD.rn_best_answer = 1
LEFT JOIN Users U_AD ON AD.AnswerOwnerUserId = U_AD.Id
LEFT JOIN LATERAL (
    SELECT t.TagName, tp.AvgScoreForTag, tp.TagPopularityQuintile
    FROM (
        SELECT unnest(string_to_array(substring(QD.Tags, 2, length(QD.Tags) - 2), '><')) AS TagName
    ) t
    JOIN TagPerformance tp ON t.TagName = tp.TagName
    ORDER BY tp.AvgScoreForTag DESC, tp.PostsWithTag DESC
    LIMIT 1
) TP ON TRUE
WHERE
    QD.QuestionCreationDate >= DATE '2021-01-01'
    AND UE.Reputation > 10000
    AND QD.QuestionViewCount > 1000
    AND (QD.AcceptedAnswerId IS NULL OR AD.AnswerScore < QD.QuestionScore * 0.75 OR AD.AnswerId IS NULL)
    AND COALESCE(PEA.TotalEdits, 0) > 5
    AND (QD.QuestionTitle LIKE 'How to optimize %' OR QD.QuestionTitle LIKE '%performance tuning%' OR QD.QuestionTitle LIKE '%scalability%' OR QD.QuestionTitle LIKE '%bottleneck%')
    AND (COALESCE(PCS.TotalComments, 0) > 10 OR COALESCE(PVA.FavoritesReceived, 0) > 5)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_CLOSE
        WHERE PH_CLOSE.PostId = QD.QuestionId
          AND PH_CLOSE.PostHistoryTypeId = 10
          AND PH_CLOSE.Comment LIKE '101%'
          AND NOT EXISTS (
              SELECT 1 FROM PostHistory PH_REOPEN WHERE PH_REOPEN.PostId = QD.QuestionId AND PH_REOPEN.PostHistoryTypeId = 11
          )
    )
ORDER BY
    WeightedPopularityScore DESC,
    GlobalEngagementRank ASC
LIMIT 100;