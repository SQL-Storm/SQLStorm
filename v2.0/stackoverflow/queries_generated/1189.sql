-- {"query": "1189.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2652} 

WITH UserStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unspecified Location') AS UserLocation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        AVG(COALESCE(P.Score, 0)) AS AveragePostScore,
        MAX(P.LastActivityDate) AS LastContentActivity,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        NULLIF(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesCountIfAny
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location
    HAVING U.Reputation > 500
       AND COUNT(DISTINCT P.Id) >= 5
       AND U.DisplayName IS NOT NULL
),
QuestionDetails AS (
    SELECT
        Q.Id AS PostId,
        Q.Title,
        Q.Body,
        Q.CreationDate,
        Q.Score,
        Q.ViewCount,
        Q.AnswerCount,
        Q.OwnerUserId,
        Q.LastEditDate,
        Q.LastActivityDate,
        Q.Tags,
        'Question' AS PostType,
        STRING_TO_ARRAY(SUBSTRING(Q.Tags FROM 2 FOR LENGTH(Q.Tags) - 2), '><') AS ParsedTags,
        CASE
            WHEN Q.Tags LIKE '%<sql>%' OR Q.Title ILIKE '%sql%' THEN 'SQL'
            WHEN Q.Tags LIKE '%<javascript>%' OR Q.Title ILIKE '%javascript%' THEN 'JavaScript'
            WHEN Q.Tags LIKE '%<python>%' OR Q.Title ILIKE '%python%' THEN 'Python'
            WHEN Q.Tags LIKE '%<java>%' OR Q.Title ILIKE '%java%' THEN 'Java'
            ELSE 'Other'
        END AS PrimaryTechCategory,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = Q.Id AND C.CreationDate > Q.CreationDate) AS CommentCountAfterCreation,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId = 2) AS LatestUpvoteDate
    FROM Posts Q
    WHERE Q.PostTypeId = 1 AND Q.CreationDate >= '2022-01-01'
      AND Q.Score >= 10 AND Q.ViewCount > 500
      AND Q.AnswerCount IS NOT NULL
),
AnswerDetails AS (
    SELECT
        A.Id AS PostId,
        A.ParentId AS QuestionId,
        A.Body,
        A.CreationDate,
        A.Score,
        A.OwnerUserId,
        A.LastEditDate,
        A.LastActivityDate,
        'Answer' AS PostType,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = A.Id AND V.VoteTypeId = 1) AS AcceptedDate,
        (SELECT Q.Title FROM Posts Q WHERE Q.Id = A.ParentId) AS ParentQuestionTitle
    FROM Posts A
    WHERE A.PostTypeId = 2 AND A.CreationDate >= '2022-01-01'
      AND A.Score >= 5
),
PostVersionHistoryAgg AS (
    SELECT
        PH.PostId,
        MAX(PH.CreationDate) AS LastHistoryDate,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 35 THEN 1 ELSE 0 END), 0) AS WasMigratedAwayFlag,
        CASE
            WHEN SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) > 0 THEN
                EXTRACT(EPOCH FROM (MAX(PH.CreationDate) - MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)))) / (24*3600)
            ELSE NULL
        END AS DaysBetweenFirstAndLastEdit,
        (SELECT CRT.Name FROM PostHistory PH_INNER JOIN CloseReasonTypes CRT ON PH_INNER.Comment::smallint = CRT.Id
         WHERE PH_INNER.PostId = PH.PostId AND PH_INNER.PostHistoryTypeId = 10
         ORDER BY PH_INNER.CreationDate DESC LIMIT 1) AS MostRecentCloseReason
    FROM PostHistory PH
    WHERE PH.CreationDate >= '2022-01-01'
    GROUP BY PH.PostId
),
LinkedPostsInfo AS (
    SELECT
        P.PostId,
        COUNT(DISTINCT P.RelatedPostId) AS NumberOfLinkedPosts,
        SUM(CASE WHEN P.LinkTypeId = 3 THEN 1 ELSE 0 END) AS NumberOfDuplicates,
        MAX(RP.Score) AS MaxRelatedPostScore,
        STRING_AGG(CASE WHEN P.LinkTypeId = 1 THEN 'LINKED' ELSE NULL END, ',') AS LinkTypeSummary
    FROM PostLinks P
    JOIN Posts RP ON P.RelatedPostId = RP.Id
    GROUP BY P.PostId
),
CombinedHighImpactPosts AS (
    SELECT
        QD.PostId,
        QD.Title,
        QD.CreationDate,
        QD.Score,
        QD.ViewCount,
        QD.AnswerCount AS RelatedCount,
        QD.OwnerUserId,
        QD.PostType,
        QD.PrimaryTechCategory,
        QD.CommentCountAfterCreation,
        NULL AS AcceptedByAnswerer,
        QD.LastEditDate,
        QD.Body AS PostBody
    FROM QuestionDetails QD
    WHERE QD.AnswerCount >= 5
      AND QD.Title IS NOT NULL
      AND QD.Body IS NOT NULL

    UNION ALL

    SELECT
        AD.PostId,
        AD.ParentQuestionTitle AS Title,
        AD.CreationDate,
        AD.Score,
        NULL AS ViewCount,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = AD.PostId) AS RelatedCount,
        AD.OwnerUserId,
        AD.PostType,
        (SELECT Q.PrimaryTechCategory FROM QuestionDetails Q WHERE Q.PostId = AD.QuestionId) AS PrimaryTechCategory,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = AD.PostId) AS CommentCountAfterCreation,
        (AD.AcceptedDate IS NOT NULL) AS AcceptedByAnswerer,
        AD.LastEditDate,
        AD.Body AS PostBody
    FROM AnswerDetails AD
    WHERE AD.Score >= 10
      AND AD.Body IS NOT NULL
)
SELECT
    CHP.PostId,
    CHP.Title,
    CHP.PostType,
    CHP.CreationDate AS PostCreationDate,
    CHP.Score AS PostScore,
    CHP.ViewCount,
    CHP.RelatedCount,
    CHP.PrimaryTechCategory,
    US.DisplayName AS PostOwnerDisplayName,
    US.Reputation AS OwnerReputation,
    US.TotalPosts AS OwnerTotalPosts,
    PVH.TotalEdits AS PostEditCount,
    PVH.TotalCloseEvents AS PostCloseCount,
    PVH.WasMigratedAwayFlag,
    PVH.MostRecentCloseReason,
    LPI.NumberOfLinkedPosts,
    LPI.NumberOfDuplicates,
    ROW_NUMBER() OVER (PARTITION BY CHP.PrimaryTechCategory ORDER BY CHP.Score DESC, CHP.CreationDate ASC) AS RankInTechCategory,
    AVG(CHP.Score) OVER (PARTITION BY US.UserId ORDER BY CHP.CreationDate ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS AvgPrevFivePostsScore,
    (COALESCE(CHP.Score, 0) * COALESCE(CHP.RelatedCount, 1) / NULLIF(CHP.ViewCount, 0)) + (US.Reputation / 1000.0) AS WeightedEngagementScore,
    CASE
        WHEN CHP.Title ILIKE '%performance%' THEN 'Performance Topic (' || LENGTH(CHP.Title) || ' chars)'
        WHEN CHP.Title ILIKE '%optimization%' THEN 'Optimization Topic (' || LENGTH(CHP.Title) || ' chars)'
        ELSE 'General Topic'
    END AS TitleKeywordAnalysis,
    (SELECT U2.DisplayName FROM Users U2 JOIN Posts P2 ON U2.Id = P2.LastEditorUserId WHERE P2.Id = CHP.PostId AND U2.Id != CHP.OwnerUserId LIMIT 1) AS LastEditorIfDifferent,
    COALESCE(TO_CHAR(CHP.LastEditDate, 'YYYY-MM-DD HH24:MI:SS'), 'Never Edited') AS FormattedLastEditDate,
    LEFT(CHP.PostBody, 200) || '...' AS PostBodyExcerpt, -- String expression for body excerpt
    -- Correlated subquery to check if the owner has a gold badge related to the primary tech category
    EXISTS (
        SELECT 1 FROM Badges B JOIN Tags T ON B.Name = T.TagName
        WHERE B.UserId = US.UserId AND B.Class = 1
          AND (CHP.PrimaryTechCategory = 'SQL' AND T.TagName ILIKE '%sql%' OR
               CHP.PrimaryTechCategory = 'JavaScript' AND T.TagName ILIKE '%javascript%' OR
               CHP.PrimaryTechCategory = 'Python' AND T.TagName ILIKE '%python%' OR
               CHP.PrimaryTechCategory = 'Java' AND T.TagName ILIKE '%java%')
    ) AS OwnerHasRelevantGoldBadge
FROM CombinedHighImpactPosts CHP
LEFT JOIN UserStats US ON CHP.OwnerUserId = US.UserId
LEFT JOIN PostVersionHistoryAgg PVH ON CHP.PostId = PVH.PostId
LEFT JOIN LinkedPostsInfo LPI ON CHP.PostId = LPI.PostId
WHERE US.UserId IS NOT NULL
  AND CHP.CreationDate >= '2023-01-01'
  AND (LPI.NumberOfDuplicates IS NULL OR LPI.NumberOfDuplicates = 0)
  AND CHP.PostBody ILIKE '%code%'
  AND NOT EXISTS (
      SELECT 1 FROM Badges B
      WHERE B.UserId = US.UserId
        AND B.Name ILIKE 'Strunk%White%'
  )
ORDER BY WeightedEngagementScore DESC, PostCreationDate DESC
LIMIT 5000;
