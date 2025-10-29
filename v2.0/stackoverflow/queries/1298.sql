-- {"query": "1298.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2581}
WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsCreated,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(P.Score) AS SumPostScore,
        SUM(P.ViewCount) AS SumPostViewCount,
        MAX(P.LastActivityDate) AS LatestPostActivity,
        MIN(P.CreationDate) AS EarliestPostCreation
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes,
        U.CreationDate, U.LastAccessDate
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.Title,
        P.Body,
        P.Tags,
        P.AcceptedAnswerId,
        P.ParentId,
        P.FavoriteCount,
        (P.Score * 0.7 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.FavoriteCount, 0) * 2.0) AS PostImpactScore,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS PostEditHistoryCount
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate BETWEEN (CAST('2024-10-01' AS DATE) - INTERVAL '3 year') AND CAST('2024-10-01' AS DATE)
),
RankedPostsPerUser AS (
    SELECT
        PDE.PostId,
        PDE.OwnerUserId,
        PDE.PostTypeId,
        PDE.PostTypeName,
        PDE.PostScore,
        PDE.PostViewCount,
        PDE.PostCreationDate,
        PDE.LastActivityDate,
        PDE.LastEditDate,
        PDE.Title,
        PDE.Body,
        PDE.Tags,
        PDE.AcceptedAnswerId,
        PDE.ParentId,
        PDE.FavoriteCount,
        PDE.PostImpactScore,
        PDE.PostEditHistoryCount,
        ROW_NUMBER() OVER (PARTITION BY PDE.OwnerUserId, PDE.PostTypeId ORDER BY PDE.PostImpactScore DESC, PDE.PostCreationDate DESC) AS rn_post_type_impact,
        RANK() OVER (PARTITION BY PDE.OwnerUserId ORDER BY PDE.PostImpactScore DESC, PDE.PostScore DESC) AS rnk_overall_best
    FROM PostDetailsExtended PDE
    WHERE PDE.PostTypeId IN (1, 2)
),
RecentModerationActivity AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS PostsAffectedByModeration,
        STRING_AGG(DISTINCT PHT.Name, ', ') AS ModerationActions,
        MAX(PH.CreationDate) AS LatestModerationActionDate
    FROM PostHistory PH
    INNER JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
      AND PH.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
      AND PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
TopTagsByInfluence AS (
    SELECT
        U.Id AS UserId,
        T.TagName,
        COUNT(DISTINCT P.Id) AS TagPostCount,
        SUM(P.Score) AS TagPostScore,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY SUM(P.Score) DESC, COUNT(DISTINCT P.Id) DESC) AS rn_tag_influence
    FROM Users U
    INNER JOIN Posts P ON U.Id = P.OwnerUserId
    INNER JOIN (
        SELECT P.Id, UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags)-2)), '><')) AS TagName
        FROM Posts P
        WHERE P.Tags IS NOT NULL AND CHAR_LENGTH(P.Tags) > 2
    ) AS PostTags ON P.Id = PostTags.Id
    INNER JOIN Tags T ON PostTags.TagName = T.TagName
    WHERE P.PostTypeId = 1
      AND U.Reputation > 5000
    GROUP BY U.Id, T.TagName
)
SELECT
    UCS.UserId,
    COALESCE(UCS.DisplayName, 'Anonymous User #' || UCS.UserId) AS UserDisplayName,
    UCS.Reputation,
    UCS.UserProfileViews,
    -- Use ISO 8601 style timestamp output via CAST to TEXT for compatibility where to_char isn't available
    CAST(UCS.LastAccessDate AS TEXT) AS LastLogin,
    CAST(UCS.UserCreationDate AS DATE) AS AccountCreation,
    UCS.TotalPostsCreated,
    UCS.TotalQuestionsCreated,
    UCS.TotalAnswersCreated,
    UCS.TotalCommentsMade,
    UCS.SumPostScore,
    UCS.SumPostViewCount,
    TPQ.Title AS TopQuestionTitle,
    TPQ.PostScore AS TopQuestionScore,
    TPQ.PostViewCount AS TopQuestionViews,
    TPQ.PostEditHistoryCount AS TopQuestionEditCount,
    TAA.PostId AS TopAnswerId,
    SUBSTRING(TAA.Body FROM 1 FOR 150) || '...' AS TopAnswerSnippet,
    TAA.PostScore AS TopAnswerScore,
    TAA.PostViewCount AS TopAnswerViews,
    TAA.PostCreationDate AS TopAnswerDate,
    COALESCE(RMA.ModerationActions, 'None') AS RecentModerationEvents,
    COALESCE(RMA.PostsAffectedByModeration, 0) AS PostsUnderModerationCount,
    TTI.TagName AS MostInfluentialTag,
    TTI.TagPostCount AS MostInfluentialTagPosts,
    TTI.TagPostScore AS MostInfluentialTagScore,
    (
        SELECT AVG((EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate))) / (60 * 60 * 24))
        FROM Posts Q
        INNER JOIN Posts A ON Q.AcceptedAnswerId = A.Id
        WHERE Q.OwnerUserId = UCS.UserId
          AND Q.PostTypeId = 1
          AND A.PostTypeId = 2
          AND Q.AcceptedAnswerId IS NOT NULL
          AND Q.CreationDate IS NOT NULL
          AND A.CreationDate IS NOT NULL
          AND Q.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '2 year')
    ) AS AvgDaysToAcceptedAnswer,
    NTILE(5) OVER (ORDER BY UCS.Reputation DESC, UCS.SumPostScore DESC) AS ReputationQuintile,
    LAG(UCS.DisplayName, 1, 'N/A') OVER (ORDER BY UCS.Reputation DESC) AS PreviousUserByReputation,
    LEAD(UCS.DisplayName, 1, 'N/A') OVER (ORDER BY UCS.Reputation DESC) AS NextUserByReputation,
    CASE
        WHEN UCS.Reputation >= 100000 AND UCS.TotalPostsCreated > 1000 THEN 'Stack Overflow Legend'
        WHEN UCS.Reputation >= 50000 AND UCS.SumPostScore > 5000 THEN 'Community Influencer'
        WHEN UCS.Reputation >= 10000 THEN 'Established Expert'
        WHEN UCS.Reputation >= 2000 THEN 'Active Contributor'
        ELSE 'Emerging Talent'
    END AS UserInfluenceTier,
    (
        SELECT CASE WHEN EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UCS.UserId AND B.Class = 1) THEN 'Yes' ELSE 'No' END
    ) AS HasGoldBadge,
    COALESCE(U.Location, 'Unknown') AS UserLocation,
    NULLIF(TRIM(REPLACE(REPLACE(U.AboutMe, CHR(10), ' '), CHR(13), ' ')), '') AS AboutMeSummary
FROM UserContributionSummary UCS
LEFT JOIN Users U ON UCS.UserId = U.Id
LEFT JOIN RankedPostsPerUser TPQ ON UCS.UserId = TPQ.OwnerUserId AND TPQ.PostTypeId = 1 AND TPQ.rn_post_type_impact = 1
LEFT JOIN RankedPostsPerUser TAA ON UCS.UserId = TAA.OwnerUserId AND TAA.PostTypeId = 2 AND TAA.rn_post_type_impact = 1
LEFT JOIN RecentModerationActivity RMA ON UCS.UserId = RMA.UserId
LEFT JOIN TopTagsByInfluence TTI ON UCS.UserId = TTI.UserId AND TTI.rn_tag_influence = 1
WHERE
    UCS.Reputation > 500
    AND UCS.TotalPostsCreated >= 3
    AND UCS.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '6 months')
    AND NOT EXISTS (
        SELECT 1
        FROM Badges B
        WHERE B.UserId = UCS.UserId
          AND LOWER(B.Name) LIKE LOWER('%Pauper%')
    )
    AND (TPQ.PostId IS NOT NULL OR TAA.PostId IS NOT NULL)
    AND CHAR_LENGTH(COALESCE(U.Location, '')) < 50
ORDER BY
    ReputationQuintile,
    UCS.Reputation DESC,
    UCS.SumPostScore DESC
LIMIT 1000;