WITH UserInfluence AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCreated,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile,
        (U.Reputation * 0.5) + (COUNT(DISTINCT P.Id) * 0.2) + (COUNT(DISTINCT B.Id) * 0.3) AS InfluenceScore
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING
        COUNT(DISTINCT P.Id) > 2
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.ParentId,
        P.AcceptedAnswerId,
        P.Title AS PostTitle,
        P.Body AS PostBody,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        COALESCE(LENGTH(P.Body) - LENGTH(REPLACE(P.Body, ' ', '')), 0) AS BodyWordCount,
        (SELECT COUNT(DISTINCT PH_edit.UserId)
         FROM PostHistory PH_edit
         WHERE PH_edit.PostId = P.Id
           AND PH_edit.PostHistoryTypeId IN (4, 5, 6)
        ) AS UniqueEditorsCount,
        (SELECT MAX(PH_latest.CreationDate)
         FROM PostHistory PH_latest
         WHERE PH_latest.PostId = P.Id
           AND PH_latest.PostHistoryTypeId IN (4, 5, 6)
        ) AS LatestEditDate,
        (SELECT AVG(C_p.Score)
         FROM Comments C_p
         WHERE C_p.PostId = P.Id
        ) AS AvgCommentScoreOnPost,
        (SELECT COUNT(*) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id AND PL.LinkTypeId = 1) AS IncomingLinksCount,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankByUser,
        CASE
            WHEN P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'Recent'
            WHEN P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years') THEN 'Medium Age'
            ELSE 'Old'
        END AS PostAgeCategory
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
)

SELECT
    'Question' AS PostType,
    UI.UserId,
    UI.DisplayName,
    UI.Reputation,
    UI.InfluenceScore,
    UI.ReputationQuintile,
    PDM.PostId,
    PDM.PostTitle AS MainContentTitle,
    PDM.PostBody AS MainContentBody,
    PDM.PostCreationDate,
    PDM.PostScore AS MainContentScore,
    PDM.ViewCount AS MainContentViewCount,
    PDM.FavoriteCount AS MainContentFavoriteCount,
    PDM.BodyWordCount,
    PDM.UniqueEditorsCount,
    PDM.LatestEditDate,
    PDM.AvgCommentScoreOnPost,
    PDM.IncomingLinksCount,
    PDM.PostScoreRankByUser,
    PDM.PostAgeCategory,
    PDM.AnswerCount AS RelatedItemCount,
    COALESCE(SUM(A_main.Score) FILTER (WHERE A_main.Score IS NOT NULL), 0) AS RelatedItemScoreSum,
    MAX(CASE WHEN PDM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
    NULL AS IsCurrentPostAcceptedAnswer,
    ROUND(
        (PDM.PostScore * 0.4) +
        (COALESCE(PDM.ViewCount, 0) * 0.01) +
        (PDM.BodyWordCount * 0.005) +
        (PDM.UniqueEditorsCount * 5) +
        (COALESCE(PDM.AvgCommentScoreOnPost, 0) * 2) +
        (PDM.IncomingLinksCount * 10) +
        (COALESCE(SUM(A_main.Score) FILTER (WHERE A_main.Score IS NOT NULL), 0) * 0.05)
    , 2) AS CombinedPostQualityScore,
    COALESCE(
        TRIM(SUBSTRING(PDM.Tags FROM POSITION('<' IN PDM.Tags) + 1 FOR POSITION('>' IN PDM.Tags) - POSITION('<' IN PDM.Tags) -1))
        , 'No Tag'
    ) AS FirstTag,
    CASE
        WHEN PDM.ClosedDate IS NOT NULL AND PDM.LastActivityDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') THEN 'Stale Closed Question'
        WHEN PDM.AnswerCount = 0 AND PDM.FavoriteCount > 5 THEN 'Unanswered Popular Question'
        WHEN PDM.PostScore >= 50 AND COALESCE(PDM.ViewCount, 0) >= 10000 AND PDM.AcceptedAnswerId IS NOT NULL THEN 'High-Value Solved Question'
        ELSE 'Other Question Type'
    END AS PostStatusCategory
FROM
    UserInfluence UI
INNER JOIN
    PostDetailedMetrics PDM ON UI.UserId = PDM.OwnerUserId
LEFT JOIN
    Posts A_main ON PDM.PostId = A_main.ParentId AND A_main.PostTypeId = 2
WHERE
    PDM.PostTypeId = 1
    AND PDM.PostScoreRankByUser <= 5
    AND PDM.BodyWordCount > 30
    AND (PDM.PostTitle LIKE '%SQL%' OR PDM.Tags LIKE '%<database>%' OR LOWER(PDM.PostBody) LIKE '%query%')
    AND PDM.AvgCommentScoreOnPost IS DISTINCT FROM -1
    AND (PDM.LatestEditDate IS NULL OR PDM.LatestEditDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year'))
GROUP BY
    UI.UserId, UI.DisplayName, UI.Reputation, UI.InfluenceScore, UI.ReputationQuintile,
    PDM.PostId, PDM.PostTitle, PDM.PostBody, PDM.PostCreationDate, PDM.PostScore, PDM.ViewCount,
    PDM.FavoriteCount, PDM.BodyWordCount, PDM.UniqueEditorsCount, PDM.LatestEditDate, PDM.AvgCommentScoreOnPost,
    PDM.IncomingLinksCount, PDM.PostScoreRankByUser, PDM.PostAgeCategory, PDM.AnswerCount, PDM.AcceptedAnswerId,
    PDM.ClosedDate, PDM.LastActivityDate, PDM.Tags
HAVING
    COUNT(DISTINCT A_main.Id) < 100

UNION ALL

SELECT
    'Answer' AS PostType,
    UI.UserId,
    UI.DisplayName,
    UI.Reputation,
    UI.InfluenceScore,
    UI.ReputationQuintile,
    PDM_ans.PostId,
    SUBSTRING(PDM_ans.PostBody FROM 1 FOR 100) AS MainContentTitle,
    PDM_ans.PostBody AS MainContentBody,
    PDM_ans.PostCreationDate,
    PDM_ans.PostScore AS MainContentScore,
    NULL AS MainContentViewCount,
    PDM_ans.FavoriteCount AS MainContentFavoriteCount,
    PDM_ans.BodyWordCount,
    PDM_ans.UniqueEditorsCount,
    PDM_ans.LatestEditDate,
    PDM_ans.AvgCommentScoreOnPost,
    PDM_ans.IncomingLinksCount,
    PDM_ans.PostScoreRankByUser,
    PDM_ans.PostAgeCategory,
    (SELECT COUNT(C_ans.Id) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) AS RelatedItemCount,
    (SELECT SUM(C_ans.Score) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) AS RelatedItemScoreSum,
    NULL AS HasAcceptedAnswer,
    MAX(CASE WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 1 ELSE 0 END) AS IsCurrentPostAcceptedAnswer,
    ROUND(
        (PDM_ans.PostScore * 0.6) +
        (PDM_ans.BodyWordCount * 0.008) +
        (PDM_ans.UniqueEditorsCount * 8) +
        (COALESCE(PDM_ans.AvgCommentScoreOnPost, 0) * 3) +
        (PDM_ans.IncomingLinksCount * 15) +
        (CASE WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 50 ELSE 0 END)
    , 2) AS CombinedPostQualityScore,
    COALESCE(
        TRIM(SUBSTRING(P_parent.Tags FROM POSITION('<' IN P_parent.Tags) + 1 FOR POSITION('>' IN P_parent.Tags) - POSITION('<' IN P_parent.Tags) -1))
        , 'No Tag'
    ) AS FirstTag,
    CASE
        WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 'Accepted Solution'
        WHEN PDM_ans.PostScore >= 20 AND PDM_ans.UniqueEditorsCount > 1 THEN 'Highly Edited Answer'
        WHEN PDM_ans.PostScore < 0 AND PDM_ans.AvgCommentScoreOnPost < 0 THEN 'Poorly Received Answer'
        ELSE 'Other Answer Type'
    END AS PostStatusCategory
FROM
    UserInfluence UI
INNER JOIN
    PostDetailedMetrics PDM_ans ON UI.UserId = PDM_ans.OwnerUserId
INNER JOIN
    Posts P_parent ON PDM_ans.ParentId = P_parent.Id
WHERE
    PDM_ans.PostTypeId = 2
    AND PDM_ans.PostScoreRankByUser <= 2
    AND PDM_ans.BodyWordCount > 20
    AND (LOWER(PDM_ans.PostBody) LIKE '%code%' OR LOWER(PDM_ans.PostBody) LIKE '%example%')
    AND PDM_ans.AvgCommentScoreOnPost IS NOT NULL
GROUP BY
    UI.UserId, UI.DisplayName, UI.Reputation, UI.InfluenceScore, UI.ReputationQuintile,
    PDM_ans.PostId, PDM_ans.PostBody, PDM_ans.PostCreationDate, PDM_ans.PostScore, PDM_ans.FavoriteCount,
    PDM_ans.BodyWordCount, PDM_ans.UniqueEditorsCount, PDM_ans.LatestEditDate, PDM_ans.AvgCommentScoreOnPost,
    PDM_ans.IncomingLinksCount, PDM_ans.PostScoreRankByUser, PDM_ans.PostAgeCategory, P_parent.AcceptedAnswerId,
    P_parent.Tags
HAVING
    (SELECT COUNT(C_ans.Id) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) < 50

ORDER BY
    InfluenceScore DESC, CombinedPostQualityScore DESC
LIMIT 2000;