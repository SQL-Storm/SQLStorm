-- {"query": "19069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1995} 
WITH UserEngagementRank AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        RANK() OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC, U.DownVotes ASC, U.CreationDate ASC) AS GlobalReputationRank
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenCount,
        SUM(CASE WHEN PH.UserId IS NOT NULL THEN 1 ELSE 0 END) AS UserHistoryActions,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment = '101' THEN 1 ELSE 0 END) AS DuplicateCloseVotes, -- Assuming '101' as close reason for duplicate
        MIN(PH.CreationDate) AS FirstHistoryDate,
        MAX(PH.CreationDate) AS LastHistoryDate
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
PostLinkMetrics AS (
    SELECT
        PL.PostId,
        COUNT(PL.Id) AS TotalLinks,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount
    FROM PostLinks AS PL
    GROUP BY PL.PostId
),
QuestionPerformance AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        COALESCE(P.CommunityOwnedDate, '1900-01-01'::timestamp) AS CommunityOwnedDate_Coalesced, -- NULL logic, type cast for safety
        P.AcceptedAnswerId,
        P.Title,
        P.Tags,
        PHA.TotalHistoryEntries,
        PHA.EditCount,
        PHA.CloseReopenCount,
        PHA.DuplicateCloseVotes,
        PLM.TotalLinks,
        PLM.LinkedPostsCount,
        PLM.DuplicatePostsCount,
        (P.Score * 0.7 + P.ViewCount * 0.05 + COALESCE(P.AnswerCount, 0) * 1.5 + COALESCE(P.CommentCount, 0) * 1.2 + COALESCE(P.FavoriteCount, 0) * 2.5) AS EngagementScore,
        (PHA.EditCount * 5 + PHA.CloseReopenCount * 10 + COALESCE(PLM.TotalLinks, 0) * 3) AS ComplexityScore,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN COALESCE(P.AnswerCount, 0) > 0 THEN 'HasAnswers'
            ELSE 'Open'
        END AS QuestionStatus,
        UPPER(SUBSTRING(COALESCE(P.Title, 'No Title'), 1, 1)) AS FirstTitleChar, -- String manipulation, NULL handling
        CASE
            WHEN P.Tags IS NULL OR P.Tags = '><' THEN 0
            ELSE ARRAY_LENGTH(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'), 1)
        END AS NumTags -- Calculate total tags for the post
    FROM Posts AS P
    LEFT JOIN PostHistoryAggregates AS PHA ON P.Id = PHA.PostId
    LEFT JOIN PostLinkMetrics AS PLM ON P.Id = PLM.PostId
    WHERE P.PostTypeId = 1 -- Only questions
),
UserAnswerStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS TotalAnswers,
        AVG(P.Score * 1.0) AS AverageAnswerScore, -- Ensure float division
        MAX(P.CreationDate) AS LastAnswerDate,
        SUM(P.Score) AS TotalAnswerScore
    FROM Posts AS P
    WHERE P.PostTypeId = 2 -- Only answers
    GROUP BY P.OwnerUserId
),
QuestionTagAnalysis AS (
    SELECT
        QP.PostId,
        COUNT(DISTINCT T.tag_value) AS DistinctTagCount -- Count distinct tags per question after unnesting
    FROM QuestionPerformance AS QP
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(QP.Tags, 2, length(QP.Tags)-2), '><')) AS T(tag_value)
    WHERE QP.Tags IS NOT NULL AND QP.Tags != '><'
    GROUP BY QP.PostId
)
SELECT
    UER.UserId,
    UER.DisplayName,
    UER.Reputation,
    UER.GlobalReputationRank,
    UER.GoldBadgesCount,
    QP.PostId,
    QP.Title,
    QP.PostCreationDate,
    QP.EngagementScore,
    QP.ComplexityScore,
    QP.QuestionStatus,
    QP.FirstTitleChar,
    UAS.TotalAnswers,
    COALESCE(UAS.AverageAnswerScore, 0.0) AS UserAvgAnswerScore, -- NULL handling for users without answers
    QTA.DistinctTagCount,
    QP.NumTags AS TotalTagsOnQuestion,
    LAG(QP.PostCreationDate, 1, UER.UserCreationDate) OVER (PARTITION BY UER.UserId ORDER BY QP.PostCreationDate) AS PreviousQuestionDate, -- Window function: LAG
    RANK() OVER (PARTITION BY UER.UserId ORDER BY QP.EngagementScore DESC, QP.ComplexityScore DESC) AS UserQuestionRank, -- Window function: RANK
    NTILE(5) OVER (ORDER BY QP.EngagementScore DESC) AS EngagementQuintile, -- Window function: NTILE
    AVG(QP.EngagementScore) OVER (PARTITION BY UER.GoldBadgesCount > 0) AS AvgEngagementScoreForBadgeGroup, -- Window function: AVG over partition
    SUM(QP.ComplexityScore) OVER (PARTITION BY QP.QuestionStatus) AS TotalComplexityScoreForStatus -- Window function: SUM over partition
FROM UserEngagementRank AS UER
INNER JOIN QuestionPerformance AS QP ON UER.UserId = QP.OwnerUserId
LEFT JOIN UserAnswerStats AS UAS ON UER.UserId = UAS.UserId
LEFT JOIN QuestionTagAnalysis AS QTA ON QP.PostId = QTA.PostId
WHERE
    UER.Reputation >= 1000
    AND UER.GoldBadgesCount >= 1
    AND QP.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    AND QP.EngagementScore > (
        SELECT AVG(InnerQP.EngagementScore) * 1.2
        FROM QuestionPerformance AS InnerQP
        WHERE InnerQP.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31'
          AND InnerQP.OwnerUserId = UER.UserId
    ) -- Correlated subquery: Compare question engagement to user's average engagement
    AND QP.ComplexityScore >= 20
    AND (QP.FirstTitleChar BETWEEN 'A' AND 'M' OR QP.FirstTitleChar IS NULL)
    AND (QP.ClosedDate IS NULL OR QP.ClosedDate > QP.PostCreationDate + INTERVAL '30 days') -- NULL logic, date arithmetic
ORDER BY
    UER.Reputation DESC,
    UserQuestionRank ASC,
    QP.PostCreationDate DESC
LIMIT 500;