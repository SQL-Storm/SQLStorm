-- {"query": "1071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2820} 

WITH UserPostSummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT PA.Id) AS AcceptedAnswerCount,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount END) AS AvgAnswersPerQuestion,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.FavoriteCount IS NOT NULL THEN P.FavoriteCount ELSE 0 END) AS TotalFavoritesOnQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN P.Id END) AS ClosedQuestionsCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts PA ON P.AcceptedAnswerId = PA.Id AND P.PostTypeId = 1 -- Accepted Answers
    GROUP BY
        U.Id, U.Reputation, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate, U.Location
),
UserHistoryAgg AS (
    SELECT
        PH.UserId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) AND P.OwnerUserId = PH.UserId THEN PH.Id END) AS SelfEditsCount, -- Edit Title, Body, Tags by owner
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS TotalClosedPostsCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 12 AND P.OwnerUserId = PH.UserId THEN PH.Id END) AS SelfDeletedPostsCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosureDate
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserTagComplexity AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS DistinctTagsCount,
        COUNT(DISTINCT CASE WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<postgresql>%' THEN 1 ELSE NULL END) AS DatabaseTagRelatedQuestions,
        ARRAY_AGG(DISTINCT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS AllTagsArray
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.OwnerUserId
),
RecentEngagement AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS RecentCommentCount,
        MAX(C.CreationDate) AS LastCommentDate,
        SUM(C.Score) AS TotalCommentScore
    FROM Comments C
    WHERE C.UserId IS NOT NULL
      AND C.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY C.UserId
),
EliteBadgeHolders AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS GoldBadgeCount,
        MAX(B.Date) AS LastGoldBadgeDate
    FROM Badges B
    WHERE B.Class = 1 -- Gold badges
    GROUP BY B.UserId
    HAVING COUNT(B.Id) >= 3
),
PostLinkAnalysis AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicateLinksCount,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinksMade
    FROM Posts P
    JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
)
-- Branch 1: Highly Reputable and Quality Focused Contributors
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes,
    U.DownVotes,
    COALESCE(UPS.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(UPS.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(UEH.SelfEditsCount, 0) AS SelfEditsCount,
    COALESCE(UTC.DistinctTagsCount, 0) AS DistinctTagsCount,
    COALESCE(EB.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(RE.RecentCommentCount, 0) AS RecentCommentCount,
    COALESCE(PLA.TotalLinksMade, 0) AS TotalLinksMade,
    'HighQualityContributor' AS ContributorCategory,
    RANK() OVER (ORDER BY U.Reputation DESC, (U.UpVotes - U.DownVotes) DESC) AS OverallRank,
    NTILE(5) OVER (ORDER BY UPS.TotalPostScore DESC) AS UserScoreQuintile,
    COALESCE(UPS.AcceptedAnswerCount * 1.0 / NULLIF(UPS.TotalQuestions, 0), 0.0) AS AcceptedAnswerRate,
    (SELECT COUNT(DISTINCT B_corr.Name) FROM Badges B_corr WHERE B_corr.UserId = U.Id AND B_corr.Class = 1) AS CorrelatedGoldBadges,
    EXISTS (
        SELECT 1 FROM Posts P_corr
        WHERE P_corr.OwnerUserId = U.Id
          AND P_corr.PostTypeId = 1
          AND P_corr.Tags LIKE '%<java>%' AND P_corr.Score > 10
    ) AS HasHighlyRatedSpecificTechQuestion,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    COALESCE(TO_CHAR(UEH.LastClosureDate, 'YYYY-MM-DD'), 'N/A') AS FormattedLastClosureDate
FROM Users U
INNER JOIN UserPostSummary UPS ON U.Id = UPS.UserId
LEFT JOIN UserHistoryAgg UEH ON U.Id = UEH.UserId
LEFT JOIN UserTagComplexity UTC ON U.Id = UTC.UserId
LEFT JOIN RecentEngagement RE ON U.Id = RE.UserId
LEFT JOIN EliteBadgeHolders EB ON U.Id = EB.UserId
LEFT JOIN PostLinkAnalysis PLA ON U.Id = PLA.UserId
WHERE U.Reputation > 5000
  AND COALESCE(UPS.TotalQuestions, 0) >= 20
  AND COALESCE(UPS.AcceptedAnswerCount * 1.0 / NULLIF(UPS.TotalQuestions, 0), 0.0) >= 0.3
  AND COALESCE(UEH.SelfEditsCount, 0) >= 10
  AND (U.LastAccessDate >= NOW() - INTERVAL '6 months' OR UPS.LastPostActivityDate >= NOW() - INTERVAL '6 months')
  AND (COALESCE(UPS.ClosedQuestionsCount, 0) * 1.0 / NULLIF(UPS.TotalQuestions, 0) < 0.2 OR COALESCE(UPS.TotalQuestions, 0) < 50)
  AND NOT EXISTS (
        SELECT 1 FROM PostHistory PH_excl
        WHERE PH_excl.UserId = U.Id
          AND PH_excl.PostHistoryTypeId = 12
          AND PH_excl.CreationDate >= NOW() - INTERVAL '3 months'
        HAVING COUNT(PH_excl.Id) > 3
  )
  AND (POSITION('Developer' IN COALESCE(U.AboutMe, '')) > 0 OR POSITION('Engineer' IN COALESCE(U.AboutMe, '')) > 0)
  AND (SELECT MAX(B3.Date) FROM Badges B3 WHERE B3.UserId = U.Id AND B3.Class = 1) IS NOT NULL

UNION ALL

-- Branch 2: Prolific and Diverse Engagers (possibly newer users, or those focusing on breadth)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes,
    U.DownVotes,
    COALESCE(UPS.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(UPS.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(UEH.SelfEditsCount, 0) AS SelfEditsCount,
    COALESCE(UTC.DistinctTagsCount, 0) AS DistinctTagsCount,
    COALESCE(EB.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(RE.RecentCommentCount, 0) AS RecentCommentCount,
    COALESCE(PLA.TotalLinksMade, 0) AS TotalLinksMade,
    'ProlificEngager' AS ContributorCategory,
    RANK() OVER (ORDER BY UPS.TotalPosts DESC, UTC.DistinctTagsCount DESC) AS OverallRank,
    NTILE(5) OVER (ORDER BY RE.TotalCommentScore DESC NULLS LAST) AS UserScoreQuintile,
    COALESCE(UPS.AcceptedAnswerCount * 1.0 / NULLIF(UPS.TotalQuestions, 0), 0.0) AS AcceptedAnswerRate,
    (SELECT COUNT(DISTINCT B_corr.Name) FROM Badges B_corr WHERE B_corr.UserId = U.Id AND B_corr.Class = 1) AS CorrelatedGoldBadges,
    EXISTS (
        SELECT 1 FROM Posts P_corr
        WHERE P_corr.OwnerUserId = U.Id
          AND P_corr.PostTypeId = 1
          AND P_corr.Tags LIKE '%<javascript>%'
          AND P_corr.CreationDate >= NOW() - INTERVAL '1 year'
    ) AS HasHighlyRatedSpecificTechQuestion,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    COALESCE(TO_CHAR(UEH.LastClosureDate, 'YYYY-MM-DD'), 'N/A') AS FormattedLastClosureDate
FROM Users U
INNER JOIN UserPostSummary UPS ON U.Id = UPS.UserId
LEFT JOIN UserHistoryAgg UEH ON U.Id = UEH.UserId
LEFT JOIN UserTagComplexity UTC ON U.Id = UTC.UserId
LEFT JOIN RecentEngagement RE ON U.Id = RE.UserId
LEFT JOIN EliteBadgeHolders EB ON U.Id = EB.UserId
LEFT JOIN PostLinkAnalysis PLA ON U.Id = PLA.UserId
WHERE U.Reputation > 1000
  AND COALESCE(UPS.TotalPosts, 0) >= 50
  AND COALESCE(UTC.DistinctTagsCount, 0) >= 10
  AND COALESCE(RE.RecentCommentCount, 0) >= 5
  AND U.CreationDate >= NOW() - INTERVAL '2 years'
  AND COALESCE(UEH.SelfDeletedPostsCount, 0) = 0
  AND (U.DisplayName IS NOT NULL AND U.DisplayName ~ '^[A-Za-z]+ [A-Za-z]+$')
  AND (
        EXISTS (
            SELECT 1 FROM Badges B_corr
            WHERE B_corr.UserId = U.Id
            AND B_corr.Name LIKE '%Scholar%'
        )
        OR
        COALESCE(UTC.DatabaseTagRelatedQuestions, 0) > 0
    )
ORDER BY OverallRank ASC, TotalLinksMade DESC
LIMIT 500;
