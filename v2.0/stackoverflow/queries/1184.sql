-- {"query": "1184.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3095}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT CASE WHEN V_Own.VoteTypeId = 2 AND V_Own.PostId IS NOT NULL THEN V_Own.PostId END) AS UpVotedPostsCount,
        COUNT(DISTINCT CASE WHEN V_Own.VoteTypeId = 3 AND V_Own.PostId IS NOT NULL THEN V_Own.PostId END) AS DownVotedPostsCount,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(P.CreationDate) AS LastPostActivity,
        (U.Reputation * 0.5) + (COUNT(DISTINCT P.Id) * 0.2) + (SUM(COALESCE(P.Score, 0)) * 0.1) + (COUNT(DISTINCT C.Id) * 0.1) AS InfluenceScore,
        COALESCE(U.Location, 'Unknown Region') AS UserLocationCategory
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V_Own ON U.Id = V_Own.UserId AND V_Own.PostId IS NOT NULL
    WHERE U.CreationDate >= DATE '2019-01-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location
    HAVING COUNT(DISTINCT P.Id) >= 5 OR COUNT(DISTINCT C.Id) >= 10
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        CASE
            WHEN P.Score >= 50 AND P.ViewCount >= 1000 AND P.FavoriteCount >= 10 THEN 'High Impact'
            WHEN P.Score >= 10 AND P.ViewCount >= 100 AND P.FavoriteCount >= 1 THEN 'Medium Impact'
            ELSE 'Low Impact'
        END AS ImpactCategory,
        (SELECT COUNT(T.TagName) FROM Tags T WHERE P.Tags LIKE '%' || T.TagName || '%') AS TagCount,
        (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<performance>%' OR P.Tags LIKE '%<javascript>%') AS IsTechRelated,
        (
            SELECT AVG(CASE WHEN V_Post.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END)
            FROM Votes V_Post
            WHERE V_Post.PostId = P.Id
        ) > COALESCE(
            (
                SELECT AVG(CASE WHEN V_OwnerAvg.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END)
                FROM Posts P_OwnerAvg
                INNER JOIN Votes V_OwnerAvg ON P_OwnerAvg.Id = V_OwnerAvg.PostId
                WHERE P_OwnerAvg.OwnerUserId = P.OwnerUserId
            ), 0.0) AS AboveOwnerAvgUpvotes,
        P.AcceptedAnswerId IS NOT NULL AS HasAcceptedAnswer
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2022-12-31'
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotesCount,
        (
            SELECT COUNT(DISTINCT U_ph.Id)
            FROM Users U_ph
            WHERE U_ph.Id IN (
                SELECT PH_inner.UserId
                FROM PostHistory PH_inner
                WHERE PH_inner.PostId = PH.PostId
                  AND PH_inner.UserId IS NOT NULL
            )
        ) AS UniqueEditors,
        MAX(CASE WHEN LOWER(PH.Comment) LIKE '%duplicate%' OR LOWER(PH.Comment) LIKE '%merge%' OR LOWER(PH.Text) LIKE '%migrated%' THEN 1 ELSE 0 END) AS HasClosureOrMigrationKeywords
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 17, 35, 36)
    GROUP BY PH.PostId
),
UserBadgeRank AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        RANK() OVER (ORDER BY SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) DESC, COUNT(B.Id) DESC) AS OverallBadgeRank
    FROM Badges B
    GROUP BY B.UserId
    HAVING COUNT(B.Id) > 0
),
HotTags AS (
    SELECT
        T.TagName
    FROM Tags T
    WHERE T.Count > 100000 AND T.IsModeratorOnly = FALSE
    ORDER BY T.Count DESC
    LIMIT 10
)
SELECT
    'High Engagement User Segment' AS UserSegmentCategory,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.InfluenceScore,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    PDE.PostId,
    PDE.Title,
    PDE.Score AS PostScore,
    PDE.ImpactCategory,
    PDE.BodyLength,
    PDE.HasAcceptedAnswer,
    PHA.TotalEdits,
    PHA.CloseVotesCount,
    PHA.UniqueEditors,
    PHA.HasClosureOrMigrationKeywords,
    UBR.GoldBadges,
    UBR.SilverBadges,
    UBR.BronzeBadges,
    UBR.OverallBadgeRank,
    NTILE(4) OVER (ORDER BY UE.InfluenceScore DESC) AS InfluenceQuartile,
    COALESCE(
        (
            SELECT AVG(P_inner.Score)
            FROM Posts P_inner
            WHERE P_inner.OwnerUserId = UE.UserId
              AND P_inner.PostTypeId = 1
              AND P_inner.CreationDate > (UE.LastAccessDate - INTERVAL '1' YEAR)
              AND EXISTS (
                  SELECT 1 FROM HotTags HT WHERE P_inner.Tags LIKE '%' || HT.TagName || '%'
              )
        ), 0.0) AS AvgHotQuestionScoreLastYear,
    COALESCE(SUBSTRING(PDE.Tags FROM POSITION('<' IN PDE.Tags) + 1 FOR (POSITION('>' IN PDE.Tags) - POSITION('<' IN PDE.Tags) - 1)), 'Untagged') AS PrimaryTag,
    (PDE.ViewCount > 1000 AND PDE.Score < 0 AND PDE.CommentCount > 5) AS IsPotentiallyControversial,
    (
        SELECT COALESCE(SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END),0) + COALESCE(SUM(CASE WHEN PL.LinkTypeId = 3 THEN 2 ELSE 0 END),0)
        FROM PostLinks PL
        WHERE PL.PostId = PDE.PostId OR PL.RelatedPostId = PDE.PostId
    ) AS TotalWeightedPostLinkReferences
FROM UserEngagement UE
INNER JOIN PostDetailsExtended PDE ON UE.UserId = PDE.OwnerUserId
LEFT JOIN PostHistoryAggregates PHA ON PDE.PostId = PHA.PostId
LEFT JOIN UserBadgeRank UBR ON UE.UserId = UBR.UserId
WHERE UE.Reputation > 5000
  AND PDE.ImpactCategory = 'High Impact'
  AND PDE.IsTechRelated = TRUE
  AND UE.UserLocationCategory NOT IN ('Unknown Region', 'Internet')

UNION ALL

SELECT
    'Moderate Engagement User Segment' AS UserSegmentCategory,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.InfluenceScore,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    NULL AS PostId,
    NULL AS Title,
    NULL AS PostScore,
    NULL AS ImpactCategory,
    NULL AS BodyLength,
    NULL AS HasAcceptedAnswer,
    NULL AS TotalEdits,
    NULL AS CloseVotesCount,
    NULL AS UniqueEditors,
    NULL AS HasClosureOrMigrationKeywords,
    UBR.GoldBadges,
    UBR.SilverBadges,
    UBR.BronzeBadges,
    UBR.OverallBadgeRank,
    NTILE(4) OVER (ORDER BY UE.InfluenceScore DESC) AS InfluenceQuartile,
    COALESCE(
        (
            SELECT AVG(P_inner.Score)
            FROM Posts P_inner
            WHERE P_inner.OwnerUserId = UE.UserId
              AND P_inner.PostTypeId = 1
              AND P_inner.CreationDate > (UE.LastAccessDate - INTERVAL '6' MONTH)
        ), 0.0) AS AvgHotQuestionScoreLastYear,
    'N/A' AS PrimaryTag,
    FALSE AS IsPotentiallyControversial,
    NULL AS TotalWeightedPostLinkReferences
FROM UserEngagement UE
LEFT JOIN UserBadgeRank UBR ON UE.UserId = UBR.UserId
WHERE UE.Reputation BETWEEN 1000 AND 5000
  AND UE.TotalPosts >= 10 AND UE.TotalPosts < 50
  AND UE.InfluenceScore > 100
  AND NOT EXISTS (
      SELECT 1 FROM Posts P_NoHotTag
      WHERE P_NoHotTag.OwnerUserId = UE.UserId
        AND P_NoHotTag.PostTypeId = 1
        AND P_NoHotTag.CreationDate > (UE.LastAccessDate - INTERVAL '6' MONTH)
        AND EXISTS (SELECT 1 FROM HotTags HT WHERE P_NoHotTag.Tags LIKE '%' || HT.TagName || '%')
  )
ORDER BY InfluenceQuartile, Reputation DESC, PostScore DESC NULLS LAST;