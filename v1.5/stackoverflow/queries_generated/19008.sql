-- {"query": "19008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2994} 

WITH UserStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.LastAccessDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS CommentCountByUser,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceivedByPosts
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.LastAccessDate
),
PostEngagement AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.LastEditDate,
        EXTRACT(DAY FROM (P.LastActivityDate - P.CreationDate)) AS DaysActive,
        P.ClosedDate,
        P.AcceptedAnswerId,
        (
            SELECT PH_Edit.CreationDate
            FROM PostHistory AS PH_Edit
            WHERE PH_Edit.PostId = P.Id
              AND PH_Edit.PostHistoryTypeId = 5 -- Edit Body
            ORDER BY PH_Edit.CreationDate ASC
            LIMIT 1
        ) AS FirstBodyEditDate,
        ARRAY(
            SELECT TRIM(REPLACE(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))), '-', '_'))
            WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
        ) AS ParsedTagsArray,
        EXISTS (
            SELECT 1 FROM PostHistory AS PH_CR
            WHERE PH_CR.PostId = P.Id
              AND PH_CR.PostHistoryTypeId = 10 -- Post Closed
              AND EXISTS (
                  SELECT 1 FROM PostHistory AS PH_RO
                  WHERE PH_RO.PostId = P.Id
                    AND PH_RO.PostHistoryTypeId = 11 -- Post Reopened
                    AND PH_RO.CreationDate > PH_CR.CreationDate
              )
        ) AS WasClosedAndReopened
    FROM Posts AS P
    WHERE P.PostTypeId = 1 -- Only Questions
      AND P.CreationDate >= '2020-01-01' -- Limit data for performance
      AND P.OwnerUserId IS NOT NULL
),
PostHistoricalSentiment AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN LOWER(PH.Text) LIKE '%bug fix%' OR LOWER(PH.Text) LIKE '%critical update%' THEN 1 END) AS BugFixHistoryCount,
        COUNT(CASE WHEN LOWER(PH.Text) LIKE '%clarification%' OR LOWER(PH.Text) LIKE '%detail%' THEN 1 END) AS ClarificationHistoryCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditEventCount,
        MAX(PH.CreationDate) AS LastHistoryEventDate
    FROM PostHistory AS PH
    WHERE PH.PostId IN (SELECT PostId FROM PostEngagement)
      AND PH.PostHistoryTypeId IN (2, 5, 4, 6)
      AND PH.CreationDate >= '2020-01-01'
    GROUP BY PH.PostId
),
UserPostRanking AS (
    SELECT
        PE.PostId,
        PE.OwnerUserId,
        PE.PostScore,
        PE.ViewCount,
        PE.AnswerCount,
        PE.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY PE.OwnerUserId ORDER BY PE.PostScore DESC, PE.ViewCount DESC) AS RankByScoreForUser,
        NTILE(4) OVER (ORDER BY PE.PostScore DESC) AS PostScoreQuartile,
        AVG(PE.PostScore) OVER (PARTITION BY PE.OwnerUserId) AS AvgUserQuestionScore,
        LEAD(PE.PostCreationDate, 1) OVER (PARTITION BY PE.OwnerUserId ORDER BY PE.PostCreationDate) AS NextPostCreationDate
    FROM PostEngagement AS PE
    WHERE PE.PostScore > 0
),
HotTopics AS (
    SELECT
        UNNEST(ParsedTagsArray) AS TagName,
        COUNT(PostId) AS TaggedPostCount,
        SUM(PostScore) AS TotalTagScore
    FROM PostEngagement
    WHERE ParsedTagsArray IS NOT NULL AND array_length(ParsedTagsArray, 1) > 0
    GROUP BY UNNEST(ParsedTagsArray)
    HAVING COUNT(PostId) > 100
),
TopEngagedQuestions AS (
    SELECT
        UPR.PostId,
        UPR.OwnerUserId,
        UPR.PostScore,
        UPR.ViewCount,
        UPR.CommentCount,
        PE.Title,
        PE.Body,
        PE.CreationDate AS PostCreationDate,
        PE.DaysActive,
        PE.FavoriteCount,
        PE.ParsedTagsArray,
        PE.FirstBodyEditDate,
        PE.WasClosedAndReopened,
        'High Score, High View' AS EngagementCategory
    FROM UserPostRanking AS UPR
    JOIN PostEngagement AS PE ON UPR.PostId = PE.PostId
    WHERE UPR.PostScore > 50 AND UPR.ViewCount > 10000
      AND UPR.RankByScoreForUser <= 5
),
ActiveQuestioners AS (
    SELECT
        U.UserId,
        U.DisplayName,
        U.Reputation,
        U.QuestionCount,
        U.AnswerCount,
        U.GoldBadges,
        U.LastAccessDate,
        SUM(CASE WHEN PE.PostScore > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
        AVG(PE.PostScore) AS AvgQuestionScore
    FROM UserStats AS U
    JOIN PostEngagement AS PE ON U.UserId = PE.OwnerUserId
    WHERE U.Reputation > 5000 AND U.QuestionCount > 10
    GROUP BY U.UserId, U.DisplayName, U.Reputation, U.QuestionCount, U.AnswerCount, U.GoldBadges, U.LastAccessDate
)
SELECT
    UQ.UserId,
    UQ.DisplayName,
    UQ.Reputation,
    UQ.QuestionCount,
    UQ.AnswerCount,
    UQ.GoldBadges,
    UQ.PositiveScoreQuestions,
    UQ.AvgQuestionScore,
    T.PostId,
    T.Title,
    T.PostScore,
    T.ViewCount,
    T.CommentCount AS PostCommentCount,
    T.EngagementCategory,
    T.FirstBodyEditDate,
    T.WasClosedAndReopened,
    PHS.BugFixHistoryCount,
    PHS.ClarificationHistoryCount,
    PHS.EditEventCount,
    PHS.LastHistoryEventDate,
    COALESCE(T.PostScore * 0.5 + T.ViewCount * 0.1 + T.CommentCount * 0.2 + T.FavoriteCount * 0.8, 0) AS EngagementIndex,
    CASE
        WHEN UQ.Reputation > 10000 AND UQ.GoldBadges >= 2 THEN 'Elite Contributor'
        WHEN UQ.Reputation > 2000 AND UQ.QuestionCount >= 5 THEN 'Active Questioner'
        ELSE 'Casual User'
    END AS UserCategory,
    (
        SELECT COUNT(DISTINCT PT.TagName)
        FROM Tags AS PT
        WHERE PT.TagName = ANY(T.ParsedTagsArray) AND PT.Count > 1000
    ) AS PopularTagsCount,
    COALESCE(HT.TaggedPostCount, 0) AS HotTopicTotalTaggedPosts,
    COALESCE(HT.TotalTagScore, 0) AS HotTopicTotalScore
FROM ActiveQuestioners AS UQ
INNER JOIN TopEngagedQuestions AS T ON UQ.UserId = T.OwnerUserId
LEFT JOIN PostHistoricalSentiment AS PHS ON T.PostId = PHS.PostId
LEFT JOIN HotTopics AS HT ON HT.TagName = ANY(T.ParsedTagsArray)
WHERE T.PostCreationDate > UQ.LastAccessDate - INTERVAL '1 year'
  AND UQ.Reputation > 0
  AND T.EngagementCategory = 'High Score, High View'
  AND (T.Body LIKE '%performance%' OR T.Body LIKE '%optimization%')
  AND T.DaysActive IS NOT NULL
  AND COALESCE(PHS.EditEventCount, 0) > 1
  AND NOT EXISTS (
        SELECT 1 FROM Posts AS A
        WHERE A.ParentId = T.PostId AND A.PostTypeId = 2 AND A.OwnerUserId = UQ.UserId AND A.Score < -5
  )
UNION ALL
SELECT
    UQ.UserId,
    UQ.DisplayName,
    UQ.Reputation,
    UQ.QuestionCount,
    UQ.AnswerCount,
    UQ.GoldBadges,
    UQ.PositiveScoreQuestions,
    UQ.AvgQuestionScore,
    PE_LVHC.PostId,
    PE_LVHC.Title,
    PE_LVHC.PostScore,
    PE_LVHC.ViewCount,
    PE_LVHC.CommentCount AS PostCommentCount,
    'Low View, High Comment' AS EngagementCategory,
    PE_LVHC.FirstBodyEditDate,
    PE_LVHC.WasClosedAndReopened,
    PHS_LVHC.BugFixHistoryCount,
    PHS_LVHC.ClarificationHistoryCount,
    PHS_LVHC.EditEventCount,
    PHS_LVHC.LastHistoryEventDate,
    COALESCE(PE_LVHC.PostScore * 0.3 + PE_LVHC.ViewCount * 0.05 + PE_LVHC.CommentCount * 0.7 + PE_LVHC.FavoriteCount * 0.5, 0) AS EngagementIndex,
    CASE
        WHEN UQ.Reputation > 10000 AND UQ.GoldBadges >= 2 THEN 'Elite Contributor'
        WHEN UQ.Reputation > 2000 AND UQ.QuestionCount >= 5 THEN 'Active Questioner'
        ELSE 'Casual User'
    END AS UserCategory,
    (
        SELECT COUNT(DISTINCT PT.TagName)
        FROM Tags AS PT
        WHERE PT.TagName = ANY(PE_LVHC.ParsedTagsArray) AND PT.Count > 1000
    ) AS PopularTagsCount,
    COALESCE(HT_LVHC.TaggedPostCount, 0) AS HotTopicTotalTaggedPosts,
    COALESCE(HT_LVHC.TotalTagScore, 0) AS HotTopicTotalScore
FROM ActiveQuestioners AS UQ
INNER JOIN PostEngagement AS PE_LVHC ON UQ.UserId = PE_LVHC.OwnerUserId
LEFT JOIN PostHistoricalSentiment AS PHS_LVHC ON PE_LVHC.PostId = PHS_LVHC.PostId
LEFT JOIN HotTopics AS HT_LVHC ON HT_LVHC.TagName = ANY(PE_LVHC.ParsedTagsArray)
WHERE PE_LVHC.PostScore < 20
  AND PE_LVHC.ViewCount < 5000
  AND PE_LVHC.CommentCount > 5
  AND PE_LVHC.WasClosedAndReopened IS TRUE
  AND PE_LVHC.DaysActive IS NOT NULL
  AND PE_LVHC.Title IS NOT NULL
  AND COALESCE(PHS_LVHC.EditEventCount, 0) >= 2
  AND EXISTS (
      SELECT 1 FROM Posts AS Ans
      WHERE Ans.ParentId = PE_LVHC.PostId AND Ans.PostTypeId = 2 AND Ans.Score > 0
  )
ORDER BY EngagementIndex DESC, Reputation DESC
LIMIT 500;
