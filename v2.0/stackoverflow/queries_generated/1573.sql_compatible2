WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 3 WHEN B.Class = 2 THEN 2 WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BadgeClassScore,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        MAX(CASE WHEN V_Received.VoteTypeId = 3 AND V_Received.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days') THEN 1 ELSE 0 END) AS HasRecentDownvoteOnTheirPosts,
        COUNT(DISTINCT P_Ans.Id) AS TotalAnswersPosted,
        COALESCE(AVG(P_Ans.Score), 0.0) AS AverageAnswerScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId AND V_Given.VoteTypeId IN (2, 3)
    LEFT JOIN Posts P_Ans ON U.Id = P_Ans.OwnerUserId AND P_Ans.PostTypeId = 2
    LEFT JOIN Votes V_Received ON P_Ans.Id = V_Received.PostId AND V_Received.VoteTypeId = 3
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostContentMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.ParentId,
        P.CreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        COALESCE(P.ClosedDate, CAST('9999-12-31 23:59:59' AS TIMESTAMP)) AS ClosedOrFutureDate,
        DATE_PART('day', P.LastActivityDate - P.CreationDate) AS PostLifespanDays,
        LENGTH(P.Body) AS BodyLength,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS MajorEditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6,8,9) THEN PH.CreationDate ELSE NULL END) AS LastContentEditHistoryDate,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id) AS DirectCommentCount,
        P.ClosedDate,
        P.Body
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.ParentId, P.CreationDate, P.LastActivityDate, P.LastEditDate,
        P.ViewCount, P.Score, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.ClosedDate, P.Body
),
QuestionSummaries AS (
    SELECT
        PCM.PostId AS QuestionId,
        PCM.OwnerUserId AS QuestionOwnerId,
        PCM.CreationDate AS QuestionCreationDate,
        PCM.LastActivityDate AS QuestionLastActivityDate,
        PCM.ViewCount,
        PCM.Score AS QuestionScore,
        PCM.AnswerCount AS DeclaredAnswerCount,
        PCM.FavoriteCount,
        PCM.Title,
        PCM.Tags,
        PCM.ClosedOrFutureDate,
        PCM.PostLifespanDays,
        PCM.BodyLength AS QuestionBodyLength,
        PCM.DirectCommentCount AS QuestionDirectCommentCount,
        PCM.TotalHistoryEntries AS QuestionTotalHistoryEntries,
        PCM.UniqueEditors AS QuestionUniqueEditors,
        PCM.MajorEditCount AS QuestionMajorEditCount,
        PCM.LastContentEditHistoryDate,
        CASE
            WHEN PCM.ViewCount >= 10000 AND PCM.Score >= 50 AND PCM.AnswerCount >= 5 THEN 'Hot Topic - High Engagement'
            WHEN PCM.ViewCount >= 1000 AND PCM.Score >= 10 THEN 'Popular Question'
            WHEN PCM.PostLifespanDays < 30 AND PCM.ViewCount < 100 AND PCM.AnswerCount = 0 THEN 'New & Unanswered'
            WHEN PCM.ClosedDate IS NOT NULL AND PCM.ClosedDate <= CAST('2024-10-01 12:34:56' AS TIMESTAMP) THEN 'Closed Or Resolved'
            ELSE 'Standard'
        END AS QuestionEngagementCategory,
        COALESCE(STRING_AGG(T.TagName, '><' ORDER BY T.Count DESC), 'untagged') AS TopTagsString,
        COUNT(DISTINCT T.TagName) AS NumberOfTags,
        SUM(T.Count) AS TotalTagPopularity
    FROM PostContentMetrics PCM
    LEFT JOIN (
        SELECT
            PCM_inner.PostId,
            TRIM(tag) AS TagNameExtracted
        FROM PostContentMetrics PCM_inner,
        LATERAL (
            SELECT UNNEST(string_to_array(SUBSTRING(PCM_inner.Tags FROM 2 FOR LENGTH(PCM_inner.Tags)-2), '><')) AS tag
        ) AS derived_tags
        WHERE PCM_inner.Tags IS NOT NULL AND LENGTH(PCM_inner.Tags) > 2
    ) AS tag_list ON tag_list.PostId = PCM.PostId
    LEFT JOIN Tags T ON T.TagName = tag_list.TagNameExtracted
    WHERE PCM.PostTypeId = 1
    GROUP BY
        PCM.PostId, PCM.OwnerUserId, PCM.CreationDate, PCM.LastActivityDate, PCM.ViewCount, PCM.Score, PCM.AnswerCount,
        PCM.FavoriteCount, PCM.Title, PCM.Tags, PCM.ClosedOrFutureDate, PCM.PostLifespanDays, PCM.BodyLength,
        PCM.DirectCommentCount, PCM.TotalHistoryEntries, PCM.UniqueEditors, PCM.MajorEditCount, PCM.LastContentEditHistoryDate,
        PCM.ClosedDate
),
AnswerAggregates AS (
    SELECT
        PCM.ParentId AS QuestionId,
        PCM.OwnerUserId AS AnswererId,
        UE.DisplayName AS AnswererDisplayName,
        COUNT(PCM.PostId) AS AnswersByThisUserToQuestion,
        SUM(PCM.Score) AS TotalScoreOnAnswers,
        AVG(PCM.Score) AS AverageScoreOnAnswers,
        SUM(PCM.BodyLength) AS TotalAnswerBodyLength,
        MAX(PCM.CreationDate) AS LastAnswerDate,
        COUNT(CASE WHEN PCM.Score >= 1 THEN 1 END) AS UpvotedAnswersCount,
        RANK() OVER (PARTITION BY PCM.ParentId ORDER BY SUM(PCM.Score) DESC, COUNT(PCM.PostId) DESC, MAX(PCM.CreationDate) DESC) AS AnswererRankForQuestion
    FROM PostContentMetrics PCM
    JOIN UserEngagement UE ON PCM.OwnerUserId = UE.UserId
    WHERE PCM.PostTypeId = 2
    GROUP BY PCM.ParentId, PCM.OwnerUserId, UE.DisplayName
)
SELECT
    QS.QuestionId,
    QS.Title,
    QS.QuestionCreationDate,
    QS.QuestionLastActivityDate,
    QS.PostLifespanDays AS QuestionLifespanDays,
    QS.ViewCount,
    QS.QuestionScore,
    QS.DeclaredAnswerCount,
    QS.FavoriteCount,
    QS.QuestionDirectCommentCount,
    QS.QuestionEngagementCategory,
    QS.TopTagsString,
    QS.NumberOfTags,
    QS.TotalTagPopularity,
    UE_Q.DisplayName AS QuestionOwnerDisplayName,
    UE_Q.Reputation AS QuestionOwnerReputation,
    UE_Q.TotalBadges AS QuestionOwnerTotalBadges,
    UE_Q.BadgeClassScore AS QuestionOwnerBadgeScore,
    QS.QuestionUniqueEditors,
    QS.QuestionMajorEditCount AS QuestionMajorContentEditCount,
    COALESCE(QS.LastContentEditHistoryDate, QS.QuestionCreationDate) AS EffectiveLastContentChangeDate,
    AA.AnswererDisplayName AS TopAnswererName,
    AA.TotalScoreOnAnswers AS TopAnswererScoreOnQuestion,
    AA.AverageScoreOnAnswers AS TopAnswererAvgScoreOnQuestion,
    AA.AnswersByThisUserToQuestion,
    UE_A.Reputation AS TopAnswererReputation,
    UE_A.TotalBadges AS TopAnswererTotalBadges,
    UE_A.HasRecentDownvoteOnTheirPosts AS TopAnswererRecentDownvoteReceived,
    NTILE(4) OVER (ORDER BY QS.ViewCount DESC, QS.QuestionScore DESC, QS.FavoriteCount DESC) AS QuestionPopularityQuartile,
    LAG(QS.QuestionScore, 1, 0) OVER (PARTITION BY QS.QuestionOwnerId ORDER BY QS.QuestionCreationDate) AS PreviousQuestionScoreByOwner,
    (QS.QuestionScore * 0.4 + QS.FavoriteCount * 0.3 + QS.QuestionDirectCommentCount * 0.2 + QS.QuestionMajorEditCount * 0.1) AS WeightedQuestionEngagementScore,
    NULLIF(QS.QuestionBodyLength, 0) AS NonZeroQuestionBodyLength,
    UPPER(SUBSTRING(QS.Title FROM 1 FOR 1)) AS FirstLetterOfTitle
FROM QuestionSummaries QS
LEFT JOIN UserEngagement UE_Q ON QS.QuestionOwnerId = UE_Q.UserId
LEFT JOIN AnswerAggregates AA ON QS.QuestionId = AA.QuestionId AND AA.AnswererRankForQuestion = 1
LEFT JOIN UserEngagement UE_A ON AA.AnswererId = UE_A.UserId
WHERE
    QS.ViewCount > 250
    AND QS.QuestionScore > 5
    AND QS.DeclaredAnswerCount >= 1
    AND QS.PostLifespanDays > 14
    AND QS.QuestionMajorEditCount >= 1
    AND (UE_A.HasRecentDownvoteOnTheirPosts IS NULL OR UE_A.HasRecentDownvoteOnTheirPosts = 0)
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = QS.QuestionId
          AND PL.LinkTypeId = 3
    )
    AND QS.QuestionCreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years') AND (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
    AND QS.QuestionEngagementCategory NOT IN ('New & Unanswered', 'Closed Or Resolved')
ORDER BY
    WeightedQuestionEngagementScore DESC,
    QS.QuestionLastActivityDate DESC,
    QuestionPopularityQuartile
LIMIT 5000;