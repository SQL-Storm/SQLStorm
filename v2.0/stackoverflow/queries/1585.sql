-- {"query": "1585.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3030}
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.Location,
        U.AboutMe,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - U.CreationDate)) / (60 * 60 * 24) AS UserLifetimeDays,
        EXISTS (
            SELECT 1
            FROM Posts P_sub
            WHERE P_sub.OwnerUserId = U.Id
              AND P_sub.PostTypeId = 1
              AND P_sub.ClosedDate IS NOT NULL
              AND P_sub.ClosedDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
        ) AS HasRecentClosedQuestion,
        NULLIF(U.Reputation, 0) / NULLIF(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - U.CreationDate)) + 1, 0) AS RepPerDay
    FROM Users U
    WHERE U.Reputation > 750
      AND U.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
),
PostComprehensiveStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId AS AnsweredQuestionId,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COUNT(DISTINCT PH.Id) AS TotalRevisions,
        MAX(PH.CreationDate) AS LatestRevisionDate,
        BOOL_OR(PH.PostHistoryTypeId IN (5, 8, 24)) AS HasBodyEditHistory,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScore,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScoreByAuthor
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
                             AND PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 24)
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years'
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.Body, P.Tags, P.CreationDate,
        P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.ParentId, P.ClosedDate,
        P.CommunityOwnedDate
),
TagAnalysis AS (
    SELECT
        P.PostId,
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        P.PostScore,
        P.OwnerUserId
    FROM PostComprehensiveStats P
    WHERE P.Tags IS NOT NULL
),
HighlyEngagedTags AS (
    SELECT
        TagName,
        COUNT(PostId) AS TaggedPostCount,
        AVG(PostScore) AS AvgTagScore
    FROM TagAnalysis
    GROUP BY TagName
    HAVING COUNT(PostId) > 5000 AND AVG(PostScore) > 5
),
UserTagContributions AS (
    SELECT
        TA.OwnerUserId AS UserId,
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS UserPostsInTag,
        AVG(TA.PostScore) AS UserAvgScoreInTag,
        RANK() OVER (PARTITION BY TA.OwnerUserId ORDER BY AVG(TA.PostScore) DESC) AS TagRankForUser
    FROM TagAnalysis TA
    JOIN HighlyEngagedTags HET ON TA.TagName = HET.TagName
    GROUP BY TA.OwnerUserId, TA.TagName
),
BadgeAggregates AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT B.Name, '; ') AS AllBadgeNamesString
    FROM Badges B
    GROUP BY B.UserId
),
GlobalAverages AS (
    SELECT
        AVG(PostScore) AS GlobalAvgPostScore,
        AVG(ViewCount) AS GlobalAvgViewCount,
        AVG(TotalRevisions) AS GlobalAvgTotalRevisions
    FROM PostComprehensiveStats
)
SELECT
    UES.UserId,
    COALESCE(UES.DisplayName, 'Anonymous') AS DisplayName,
    'High-Impact Questioner' AS RoleCategory,
    UES.Reputation,
    UES.UserCreationDate,
    PCS.PostId AS EntityId,
    PCS.Title AS EntityTitle,
    PCS.PostScore AS EntityScore,
    PCS.ViewCount AS EntityViews,
    PCS.PostCommentCount AS EntityCommentCount,
    PCS.FavoriteCount AS EntityFavoriteCount,
    PCS.TotalRevisions AS EntityRevisions,
    PCS.LastEditDate AS EntityLastEditDate,
    (PCS.PostScore * 0.4 + PCS.ViewCount * 0.0005 + COALESCE(PCS.AnswerCount, 0) * 0.15 + PCS.PostCommentCount * 0.05 + PCS.FavoriteCount * 0.1 + PCS.TotalRevisions * 0.02 +
     (CASE WHEN PCS.AcceptedAnswerId IS NOT NULL THEN 0.2 ELSE 0 END) * PCS.PostScore
    ) AS CombinedQualityScore,
    RANK() OVER (PARTITION BY UES.UserId ORDER BY PCS.PostScore DESC, PCS.ViewCount DESC) AS UserEntityRank,
    (PCS.PostScore > GA.GlobalAvgPostScore) AS IsAboveGlobalAvgScore,
    (PCS.ViewCount > GA.GlobalAvgViewCount) AS IsAboveGlobalAvgViews,
    (PCS.TotalRevisions > GA.GlobalAvgTotalRevisions) AS IsAboveGlobalAvgRevisions,
    BA.GoldBadges,
    BA.SilverBadges,
    BA.BronzeBadges,
    UES.HasRecentClosedQuestion,
    (UES.AboutMe LIKE '%developer%' OR UES.AboutMe LIKE '%engineer%' OR UES.AboutMe LIKE '%programmer%') AS IsTechProfessional,
    (SELECT STRING_AGG(UTC.TagName || ' (' || ROUND(UTC.UserAvgScoreInTag, 1) || ')', '; ') FROM UserTagContributions UTC WHERE UTC.UserId = UES.UserId AND UTC.TagRankForUser <= 3) AS TopTagContributionsSummary,
    COALESCE(PCS.Tags, 'N/A') AS PostTags
FROM UserEngagementSummary UES
JOIN PostComprehensiveStats PCS ON UES.UserId = PCS.OwnerUserId
LEFT JOIN BadgeAggregates BA ON UES.UserId = BA.UserId
CROSS JOIN GlobalAverages GA
WHERE PCS.PostTypeId = 1
  AND PCS.PostScore > 20
  AND PCS.ViewCount > 1000
  AND PCS.AcceptedAnswerId IS NOT NULL
  AND PCS.ClosedDate IS NULL
  AND EXISTS (
        SELECT 1 FROM PostLinks PL WHERE PL.PostId = PCS.PostId AND PL.LinkTypeId = 1
    )
  AND PCS.HasBodyEditHistory
  AND PCS.RollingAvgUserPostScore > 10
UNION ALL
SELECT
    UES.UserId,
    COALESCE(UES.DisplayName, 'Anonymous') AS DisplayName,
    'Top Answer Provider' AS RoleCategory,
    UES.Reputation,
    UES.UserCreationDate,
    PCS.PostId AS EntityId,
    NULL AS EntityTitle,
    PCS.PostScore AS EntityScore,
    NULL AS EntityViews,
    PCS.PostCommentCount AS EntityCommentCount,
    PCS.FavoriteCount AS EntityFavoriteCount,
    PCS.TotalRevisions AS EntityRevisions,
    PCS.LastEditDate AS EntityLastEditDate,
    (PCS.PostScore * 0.5 + PCS.PostCommentCount * 0.1 + PCS.FavoriteCount * 0.15 + PCS.TotalRevisions * 0.03 +
     (CASE WHEN ParentQ.AcceptedAnswerId = PCS.PostId THEN 0.2 ELSE 0 END) * PCS.PostScore +
     (PCS.PostScore - PCS.PreviousPostScoreByAuthor) * 0.01
    ) AS CombinedQualityScore,
    NTILE(4) OVER (PARTITION BY UES.UserId ORDER BY PCS.PostScore DESC, PCS.LastEditDate DESC) AS UserEntityRank,
    (PCS.PostScore > GA.GlobalAvgPostScore) AS IsAboveGlobalAvgScore,
    FALSE AS IsAboveGlobalAvgViews,
    (PCS.TotalRevisions > GA.GlobalAvgTotalRevisions) AS IsAboveGlobalAvgRevisions,
    BA.GoldBadges,
    BA.SilverBadges,
    BA.BronzeBadges,
    UES.HasRecentClosedQuestion,
    (UES.AboutMe LIKE '%mentor%' OR UES.AboutMe LIKE '%expert%' OR UES.AboutMe LIKE '%specialist%') AS IsTechProfessional,
    (SELECT STRING_AGG(UTC.TagName || ' (' || ROUND(UTC.UserAvgScoreInTag, 1) || ')', '; ') FROM UserTagContributions UTC WHERE UTC.UserId = UES.UserId AND UTC.TagRankForUser <= 3) AS TopTagContributionsSummary,
    COALESCE(PCS.Tags, 'N/A') AS PostTags
FROM UserEngagementSummary UES
JOIN PostComprehensiveStats PCS ON UES.UserId = PCS.OwnerUserId
LEFT JOIN PostComprehensiveStats ParentQ ON PCS.AnsweredQuestionId = ParentQ.PostId
LEFT JOIN BadgeAggregates BA ON UES.UserId = BA.UserId
CROSS JOIN GlobalAverages GA
WHERE PCS.PostTypeId = 2
  AND PCS.PostScore > 15
  AND PCS.PostCommentCount > 2
  AND PCS.LastEditDate IS NOT NULL
  AND (ParentQ.AcceptedAnswerId = PCS.PostId OR PCS.FavoriteCount > 0)
  AND PCS.CommunityOwnedDate IS NULL
  AND NOT EXISTS (
        SELECT 1 FROM PostHistory PH WHERE PH.PostId = PCS.PostId AND PH.PostHistoryTypeId = 12
    )
ORDER BY
    RoleCategory,
    CombinedQualityScore DESC,
    Reputation DESC
LIMIT 750;