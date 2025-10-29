-- {"query": "1601.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2460} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS LatestGoldBadgeDate,
        MIN(U.CreationDate) OVER (PARTITION BY COALESCE(U.Location, 'Unknown')) AS MinCreationDateInLocationGroup,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionActivitySummary AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.ClosedDate AS QuestionClosedDate,
        Q.CommunityOwnedDate AS QuestionCommunityOwnedDate,
        Q.Title AS QuestionTitle,
        Q.Tags AS QuestionTags,
        COUNT(A.Id) AS ActualAnswerCount, -- count answers related by ParentId
        SUM(A.Score) AS TotalAnswerScore,
        AVG(A.Score) AS AvgAnswerScoreForQuestion,
        MAX(C.Score) AS MaxCommentScoreOnQuestion,
        MIN(C.CreationDate) AS FirstCommentDateOnQuestion,
        MAX(C.CreationDate) AS LastCommentDateOnQuestion,
        LAG(Q.CreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PrevQuestionDateByOwner,
        COALESCE(Q.FavoriteCount, 0) + (COALESCE(Q.ViewCount, 0) / 100.0) AS QuestionEngagementMetric
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    LEFT JOIN Comments C ON Q.Id = C.PostId
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.FavoriteCount, Q.AnswerCount, Q.ClosedDate, Q.CommunityOwnedDate, Q.Title, Q.Tags
),
PostEditHistory AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_edit,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditDate,
        LEAD(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEditDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
DuplicateLinkAnalysis AS (
    SELECT
        PL.PostId AS QuestionId,
        COUNT(DISTINCT PL.RelatedPostId) AS DuplicateCount,
        MAX(PL.CreationDate) AS LatestDuplicateLinkDate,
        MIN(PL.CreationDate) AS EarliestDuplicateLinkDate
    FROM PostLinks PL
    WHERE PL.LinkTypeId = 3 -- Duplicate
    GROUP BY PL.PostId
),
TagPerformance AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        T.Count AS TagUseCount,
        SUM(QAS.QuestionScore) AS TotalScoreForTag,
        AVG(QAS.QuestionEngagementMetric) AS AvgEngagementForTag,
        DENSE_RANK() OVER (ORDER BY T.Count DESC, SUM(QAS.QuestionScore) DESC) AS TagPopularityRank
    FROM Tags T
    INNER JOIN QuestionActivitySummary QAS ON QAS.QuestionTags LIKE '%' || T.TagName || '%' -- Potentially slow, but complex
    GROUP BY T.Id, T.TagName, T.Count
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationQuintile,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.GoldBadges,
    UE.LatestGoldBadgeDate,
    UE.UserCreationDate,
    UE.UserLastAccessDate,
    UE.UserViews,
    UE.UserUpVotes,
    UE.UserDownVotes,
    COALESCE(UE.AvgQuestionScore, 0.0) AS UserAvgQuestionScore,
    COALESCE(UE.AvgAnswerScore, 0.0) AS UserAvgAnswerScore,
    QA.QuestionId,
    QA.QuestionTitle,
    QA.QuestionScore,
    QA.QuestionViewCount,
    QA.QuestionFavoriteCount,
    QA.QuestionEngagementMetric,
    QA.ActualAnswerCount,
    QA.TotalAnswerScore,
    QA.AvgAnswerScoreForQuestion,
    QA.MaxCommentScoreOnQuestion,
    QA.QuestionClosedDate,
    LE.EditDate AS LastEditDate,
    LE.EditorUserId AS LastEditorUserId,
    EXTRACT(EPOCH FROM (LE.EditDate - LE.PreviousEditDate)) / 3600.0 AS HoursSincePreviousEdit,
    DLA.DuplicateCount,
    TP.TagName AS TopQuestionTag,
    TP.TagUseCount AS TopQuestionTagUseCount,
    TP.AvgEngagementForTag AS TopQuestionTagAvgEngagement,
    TP.TagPopularityRank AS TopQuestionTagRank,
    (
        SELECT COUNT(DISTINCT C2.Id)
        FROM Comments C2
        WHERE C2.PostId = QA.QuestionId
          AND C2.CreationDate >= QA.QuestionCreationDate + INTERVAL '7 days'
          AND C2.Score > 0
    ) AS PositiveCommentsAfterFirstWeek,
    (
        SELECT MAX(P_Related.ViewCount)
        FROM PostLinks PL_Corr
        JOIN Posts P_Related ON PL_Corr.RelatedPostId = P_Related.Id
        WHERE PL_Corr.PostId = QA.QuestionId
          AND PL_Corr.LinkTypeId = 3 -- Duplicate
    ) AS MaxDuplicatePostViewCount,
    CASE
        WHEN QA.QuestionClosedDate IS NOT NULL AND DLA.DuplicateCount > 0 THEN 'ClosedAndDuplicate'
        WHEN QA.QuestionClosedDate IS NOT NULL THEN 'ClosedOnly'
        WHEN DLA.DuplicateCount > 0 THEN 'DuplicateOnly'
        WHEN QA.QuestionFavoriteCount >= 100 THEN 'HighlyFavorited'
        WHEN QA.QuestionViewCount >= 5000 THEN 'HighlyViewed'
        ELSE 'Regular'
    END AS QuestionStatusCategory,
    COALESCE(NULLIF(UE.UserUpVotes, 0)::numeric / NULLIF(UE.UserDownVotes, 0), 0) AS UpDownVoteRatio,
    UE.MinCreationDateInLocationGroup,
    UE.TotalQuestions - UE.TotalAnswers AS QuestionAnswerDifference,
    UPPER(SUBSTRING(UE.DisplayName, 1, 3) || '-' || LPAD(UE.Reputation::text, 10, '0')) AS UserIdentifierHash,
    BOOL_OR(UE.Reputation > 10000 AND UE.GoldBadges > 0) OVER (PARTITION BY QA.QuestionId) AS IsHighRepUserQuestion
FROM UserEngagement UE
INNER JOIN QuestionActivitySummary QA ON UE.UserId = QA.OwnerUserId
LEFT JOIN LATERAL (SELECT * FROM PostEditHistory PEH WHERE PEH.PostId = QA.QuestionId ORDER BY PEH.EditDate DESC LIMIT 1) LE ON TRUE
LEFT JOIN DuplicateLinkAnalysis DLA ON QA.QuestionId = DLA.QuestionId
LEFT JOIN LATERAL (
    SELECT T_Inner.TagName, TP_Inner.TagUseCount, TP_Inner.AvgEngagementForTag, TP_Inner.TagPopularityRank
    FROM UNNEST(string_to_array(SUBSTRING(QA.QuestionTags, 2, LENGTH(QA.QuestionTags) - 2), '><')) AS q_tag_exploded
    JOIN TagPerformance TP_Inner ON TP_Inner.TagName = q_tag_exploded
    ORDER BY TP_Inner.TagPopularityRank ASC
    LIMIT 1
) TP ON TRUE
WHERE UE.Reputation > 500
  AND QA.QuestionCreationDate BETWEEN NOW() - INTERVAL '2 year' AND NOW()
  AND QA.QuestionViewCount > 100
  AND NOT EXISTS (
      SELECT 1
      FROM PostHistory PH_Closure
      WHERE PH_Closure.PostId = QA.QuestionId
        AND PH_Closure.PostHistoryTypeId = 10 -- Post Closed
        AND PH_Closure.CreationDate > QA.QuestionCreationDate + INTERVAL '1 month'
        AND PH_Closure.UserId IS NULL -- Community closure, often implies more controversy
  )
  AND (UE.UserViews > UE.TotalPosts * 10 OR UE.TotalAnswers > 50)
  AND (LOWER(UE.DisplayName) LIKE '%dev%' OR UE.AboutMe IS NOT NULL AND POSITION('SQL' IN UPPER(UE.AboutMe)) > 0)
ORDER BY QA.QuestionEngagementMetric DESC, UE.Reputation DESC, LE.EditDate DESC
LIMIT 1000;
