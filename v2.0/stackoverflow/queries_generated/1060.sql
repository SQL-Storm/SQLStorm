-- {"query": "1060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2348} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id) AS TotalBadges,
        U.LastAccessDate,
        CASE
            WHEN U.Reputation >= 100000 THEN 'Legendary'
            WHEN U.Reputation >= 25000 THEN 'Veteran'
            WHEN U.Reputation >= 5000 THEN 'Expert'
            WHEN U.Reputation >= 1000 THEN 'Advanced'
            WHEN U.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Novice'
        END AS ReputationTier,
        COALESCE((SELECT AVG(CAST(C.Score AS NUMERIC)) FROM Comments C WHERE C.UserId = U.Id), 0) AS AvgCommentScore
    FROM Users U
),
PostActivitySummary AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8) THEN PH.Id END) AS TotalEdits,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        SUM(CASE WHEN C.Id IS NOT NULL THEN C.Score ELSE 0 END) AS TotalCommentScoreOnPost,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.AcceptedAnswerId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        STRING_AGG(DISTINCT T.TagName, ', ') AS TagsList,
        COUNT(DISTINCT T.Id) AS UniqueTagCount,
        BOOL_AND(T.WikiPostId IS NOT NULL AND T.ExcerptPostId IS NOT NULL) AS AllTagsHaveWiki,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesForTags,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesForTags,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesForTags
    FROM Posts P
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName_UNNEST ON TRUE
    LEFT JOIN Tags T ON TagName_UNNEST = T.TagName
    LEFT JOIN Badges B ON T.TagName = B.Name AND B.TagBased = TRUE
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.Id
),
RelatedPostAnalysis AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedPosts,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicatePostsCount,
        MAX(CASE WHEN PL.LinkTypeId = 3 AND (SELECT COALESCE(PP.Score, 0) FROM Posts PP WHERE PP.Id = PL.RelatedPostId) > COALESCE(P.Score, 0) * 2 THEN 1 ELSE 0 END) AS HasSignificantlyHigherScoredDuplicate
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id
),
QuestionMetrics AS (
    SELECT
        PAS.PostId,
        P.Title,
        UE.UserDisplayName AS OwnerDisplayName,
        UE.ReputationTier,
        PAS.PostCreationDate,
        PAS.LastActivityDate,
        PAS.Score,
        PAS.ViewCount,
        PAS.AnswerCount,
        COALESCE(PAS.FavoriteCount, 0) AS FavoriteCount,
        PAS.TotalEdits,
        PAS.TotalCommentsOnPost,
        PAS.TotalCommentScoreOnPost,
        TA.TagsList,
        TA.UniqueTagCount,
        TA.AllTagsHaveWiki,
        COALESCE(RPA.TotalRelatedPosts, 0) AS TotalRelatedPosts,
        COALESCE(RPA.LinkedPostsCount, 0) AS LinkedPostsCount,
        COALESCE(RPA.DuplicatePostsCount, 0) AS DuplicatePostsCount,
        COALESCE(RPA.HasSignificantlyHigherScoredDuplicate, 0) AS HasSignificantlyHigherScoredDuplicate,
        PAS.PostStatus,
        UE.AvgCommentScore AS OwnerAvgCommentScore,
        (PAS.Score * 0.5 + PAS.TotalCommentsOnPost * 0.2 + PAS.TotalEdits * 0.1 + PAS.ViewCount * 0.001 + COALESCE(PAS.FavoriteCount, 0) * 0.3) AS ActivityScore,
        EXTRACT(EPOCH FROM (NOW() - PAS.PostCreationDate)) / 86400.0 AS DaysSinceCreation
    FROM PostActivitySummary PAS
    JOIN Posts P ON PAS.PostId = P.Id
    LEFT JOIN UserEngagement UE ON PAS.OwnerUserId = UE.UserId
    LEFT JOIN TagAnalysis TA ON PAS.PostId = TA.PostId
    LEFT JOIN RelatedPostAnalysis RPA ON PAS.PostId = RPA.PostId
    WHERE P.Title IS NOT NULL
      AND PAS.Score > 0
      AND PAS.ViewCount > 100
),
HighActivityControversialPosts AS (
    SELECT
        QM.PostId
    FROM QuestionMetrics QM
    WHERE QM.ActivityScore > 100
      AND QM.TotalEdits > 5
      AND QM.TotalCommentsOnPost > 10
      AND QM.TotalCommentScoreOnPost < 0
      AND (QM.TagsList ILIKE '%<sql>%' OR QM.TagsList ILIKE '%<performance>%')
      AND QM.PostStatus = 'Open'
),
ExpertAnsweredPosts AS (
    SELECT
        QM.PostId
    FROM QuestionMetrics QM
    WHERE QM.ReputationTier IN ('Expert', 'Veteran', 'Legendary')
      AND QM.AnswerCount >= 5
      AND QM.TotalEdits <= 2
      AND QM.PostStatus = 'Answered'
)
SELECT
    QM.PostId,
    QM.Title,
    QM.OwnerDisplayName,
    QM.ReputationTier,
    QM.PostCreationDate,
    QM.LastActivityDate,
    QM.Score,
    QM.ViewCount,
    QM.AnswerCount,
    QM.FavoriteCount,
    QM.TotalEdits,
    QM.TotalCommentsOnPost,
    QM.TotalCommentScoreOnPost,
    QM.TagsList,
    QM.UniqueTagCount,
    QM.AllTagsHaveWiki,
    QM.TotalRelatedPosts,
    QM.LinkedPostsCount,
    QM.DuplicatePostsCount,
    QM.HasSignificantlyHigherScoredDuplicate,
    QM.PostStatus,
    QM.ActivityScore,
    QM.DaysSinceCreation,
    QM.OwnerAvgCommentScore,
    COALESCE(CAST(QM.TotalEdits AS NUMERIC) / NULLIF(QM.TotalCommentsOnPost, 0), 0) AS EditToCommentRatio,
    RANK() OVER (PARTITION BY QM.ReputationTier ORDER BY QM.ActivityScore DESC, QM.PostId) AS RankByActivityScore,
    AVG(QM.Score) OVER (PARTITION BY EXTRACT(YEAR FROM QM.PostCreationDate), EXTRACT(MONTH FROM QM.PostCreationDate)) AS AvgMonthlyPostScore,
    COALESCE(QM.Score - LAG(QM.Score, 1, QM.Score) OVER (PARTITION BY QM.OwnerDisplayName ORDER BY QM.PostCreationDate), 0) AS ScoreDiffFromPreviousPost,
    SUBSTRING(QM.Title, 1, 50) || (CASE WHEN LENGTH(QM.Title) > 50 THEN '...' ELSE '' END) AS ShortTitlePreview,
    (QM.Title ILIKE '%sql%' OR QM.Title ILIKE '%database%' OR QM.TagsList ILIKE '%<database>%') AS IsDatabaseRelated,
    COALESCE(CAST(QM.FavoriteCount AS VARCHAR), 'No Favorites Recorded') AS FavoriteCountDisplay,
    (
        QM.ActivityScore > 100
        AND QM.TotalEdits > 5
        AND QM.TotalCommentsOnPost > 10
        AND QM.TotalCommentScoreOnPost < 0
        AND (QM.TagsList ILIKE '%<sql>%' OR QM.TagsList ILIKE '%<performance>%')
        AND QM.PostStatus = 'Open'
    ) AS IsHighEngagementControversial
FROM QuestionMetrics QM
WHERE QM.PostId IN (SELECT PostId FROM HighActivityControversialPosts EXCEPT SELECT PostId FROM ExpertAnsweredPosts)
ORDER BY QM.ActivityScore DESC, QM.PostId
LIMIT 100;
