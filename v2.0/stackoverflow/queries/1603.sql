-- {"query": "1603.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3513}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreOwned,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 2) AS TotalUpvotesGiven,
        (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 3) AS TotalDownvotesGiven,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (5, 6)) AS TotalEditsMade
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate
),
PostComplexMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        (
            SELECT SUM(C.Score)
            FROM Comments C
            WHERE C.PostId = P.Id
        ) AS TotalCommentScore,
        (
            SELECT AVG(LENGTH(C.Text))
            FROM Comments C
            WHERE C.PostId = P.Id
        ) AS AvgCommentLength,
        COALESCE(LENGTH(P.Body), 0) AS BodyLength,
        CASE
            WHEN P.Tags IS NULL OR LENGTH(P.Tags) <= 2 THEN 0
            ELSE CARDINALITY(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))
        END AS TagCount,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        (
            SELECT COUNT(DISTINCT PH.Id)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCount,
        LAG(P.LastEditDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostEditDate,
        LEAD(P.LastEditDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostEditDate,
        FIRST_VALUE(P.Id) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS FirstPostOfUser,
        LAST_VALUE(P.Id) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastPostOfUser
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
),
PostTagsExpanded AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS Tag
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
TopTagsByPostType AS (
    SELECT
        PTE.Tag,
        PTE.PostTypeId,
        COUNT(PTE.PostId) AS TaggedPostCount
    FROM PostTagsExpanded PTE
    INNER JOIN Posts P ON PTE.PostId = P.Id
    WHERE P.PostTypeId = 1 AND P.Score >= 10
    GROUP BY PTE.Tag, PTE.PostTypeId
    HAVING COUNT(PTE.PostId) > 50
),
UserBadgeAchievements AS (
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Name = 'Disciplined' THEN 1 ELSE 0 END) AS HasDisciplinedBadge,
        SUM(CASE WHEN B.Name = 'Unsung Hero' THEN 1 ELSE 0 END) AS HasUnsungHeroBadge
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserProfileViews,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalCommentsMade,
    UAS.TotalPostViewsOwned,
    UAS.TotalPostScoreOwned,
    UAS.TotalEditsMade,
    UBA.TotalBadges,
    UBA.GoldBadges,
    UBA.SilverBadges,
    UBA.HasDisciplinedBadge,
    UBA.HasUnsungHeroBadge,
    SUM(CASE WHEN PCM.HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
    SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsOwned,
    SUM(CASE WHEN PCM.AvgCommentLength IS NOT NULL AND PCM.AvgCommentLength > 100 THEN 1 ELSE 0 END) AS PostsWithLongComments,
    AVG(PCM.PostScore) AS AvgPostScoreOwned,
    AVG(PCM.CommentCount) AS AvgCommentCountOwned,
    AVG(EXTRACT(epoch FROM (PCM.NextPostEditDate - PCM.PrevPostEditDate)) / 3600) AS AvgHoursBetweenEdits,
    RANK() OVER (ORDER BY UAS.TotalPostScoreOwned DESC, UAS.TotalPostsOwned DESC) AS UserEngagementRank,
    NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile,
    (
        SELECT COUNT(DISTINCT PL.RelatedPostId)
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT PCM_sub.PostId FROM PostComplexMetrics PCM_sub WHERE PCM_sub.OwnerUserId = U.Id AND PCM_sub.PostTypeId = 1)
          AND PL.LinkTypeId = 3
    ) AS DuplicatedQuestionLinksOwned,
    COALESCE(NULLIF(U.Location, ''), 'Unknown') AS UserLocationStatus,
    CASE
        WHEN U.Reputation >= 10000 AND UBA.GoldBadges >= 3 THEN 'Guru'
        WHEN U.Reputation >= 5000 AND UBA.SilverBadges >= 5 THEN 'Expert'
        WHEN U.Reputation >= 1000 THEN 'Pro'
        ELSE 'Contributor'
    END AS UserCategory,
    STRING_AGG(DISTINCT TT.Tag, ', ') FILTER (WHERE TT.Tag IS NOT NULL) AS TopTagsOfInterest,
    (DATE '2024-10-01' - CAST(MAX(U.LastAccessDate) AS date)) AS DaysSinceLastAccess
FROM Users U
INNER JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgeAchievements UBA ON U.Id = UBA.UserId
LEFT JOIN PostComplexMetrics PCM ON U.Id = PCM.OwnerUserId
LEFT JOIN Posts P ON PCM.PostId = P.Id
LEFT JOIN PostTagsExpanded PTE_main ON P.Id = PTE_main.PostId
LEFT JOIN TopTagsByPostType TT ON PTE_main.Tag = TT.Tag AND PTE_main.PostTypeId = TT.PostTypeId
WHERE
    U.Reputation >= 500
    AND UAS.TotalPostsOwned > 5
    AND EXISTS (
        SELECT 1
        FROM Badges B_inner
        WHERE B_inner.UserId = U.Id
          AND B_inner.Name IN ('Autobiographer', 'Curious')
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH
        WHERE PH.UserId = U.Id
          AND PH.PostHistoryTypeId = 10
          AND PH.CreationDate > (U.LastAccessDate - INTERVAL '1 year')
    )
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.Views, UAS.TotalPostsOwned, UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned, UAS.TotalCommentsMade, UAS.TotalPostViewsOwned,
    UAS.TotalPostScoreOwned, UAS.TotalEditsMade, UBA.TotalBadges, UBA.GoldBadges,
    UBA.SilverBadges, UBA.HasDisciplinedBadge, UBA.HasUnsungHeroBadge,
    U.Location, U.LastAccessDate, UAS.TotalPostsOwned, UAS.TotalPostScoreOwned
HAVING
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
    OR SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) > 0
UNION ALL
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserProfileViews,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalCommentsMade,
    UAS.TotalPostViewsOwned,
    UAS.TotalPostScoreOwned,
    UAS.TotalEditsMade,
    UBA.TotalBadges,
    UBA.GoldBadges,
    UBA.SilverBadges,
    UBA.HasDisciplinedBadge,
    UBA.HasUnsungHeroBadge,
    SUM(CASE WHEN PCM.HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
    SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsOwned,
    SUM(CASE WHEN PCM.AvgCommentLength IS NOT NULL AND PCM.AvgCommentLength > 100 THEN 1 ELSE 0 END) AS PostsWithLongComments,
    AVG(PCM.PostScore) AS AvgPostScoreOwned,
    AVG(PCM.CommentCount) AS AvgCommentCountOwned,
    AVG(EXTRACT(epoch FROM (PCM.NextPostEditDate - PCM.PrevPostEditDate)) / 3600) AS AvgHoursBetweenEdits,
    RANK() OVER (ORDER BY UAS.TotalPostScoreOwned DESC, UAS.TotalPostsOwned DESC) AS UserEngagementRank,
    NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile,
    (
        SELECT COUNT(DISTINCT PL.RelatedPostId)
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT PCM_sub.PostId FROM PostComplexMetrics PCM_sub WHERE PCM_sub.OwnerUserId = U.Id AND PCM_sub.PostTypeId = 1)
          AND PL.LinkTypeId = 3
    ) AS DuplicatedQuestionLinksOwned,
    COALESCE(NULLIF(U.Location, ''), 'Unknown') AS UserLocationStatus,
    'Duplicate_Focus_User' AS UserCategory,
    STRING_AGG(DISTINCT TT.Tag, ', ') FILTER (WHERE TT.Tag IS NOT NULL) AS TopTagsOfInterest,
    (DATE '2024-10-01' - CAST(MAX(U.LastAccessDate) AS date)) AS DaysSinceLastAccess
FROM Users U
INNER JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgeAchievements UBA ON U.Id = UBA.UserId
INNER JOIN Posts P ON U.Id = P.OwnerUserId
INNER JOIN PostComplexMetrics PCM ON P.Id = PCM.PostId
LEFT JOIN PostTagsExpanded PTE_main ON P.Id = PTE_main.PostId
LEFT JOIN TopTagsByPostType TT ON PTE_main.Tag = TT.Tag AND PTE_main.PostTypeId = TT.PostTypeId
WHERE
    U.Reputation < 5000
    AND P.PostTypeId = 1
    AND P.ClosedDate IS NOT NULL
    AND EXISTS (
        SELECT 1
        FROM PostLinks PL_inner
        WHERE PL_inner.PostId = P.Id
          AND PL_inner.LinkTypeId = 3
    )
    AND NOT EXISTS (
        SELECT 1
        FROM Comments C_inner
        WHERE C_inner.PostId = P.Id
          AND C_inner.Text LIKE '%reopen%'
    )
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.Views, UAS.TotalPostsOwned, UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned, UAS.TotalCommentsMade, UAS.TotalPostViewsOwned,
    UAS.TotalPostScoreOwned, UAS.TotalEditsMade, UBA.TotalBadges, UBA.GoldBadges,
    UBA.SilverBadges, UBA.HasDisciplinedBadge, UBA.HasUnsungHeroBadge,
    U.Location, U.LastAccessDate, P.Id
HAVING
    COUNT(DISTINCT P.Id) > 1
ORDER BY
    UserEngagementRank ASC, DaysSinceLastAccess DESC;