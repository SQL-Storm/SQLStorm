-- {"query": "1658.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2526}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User #' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        MAX(P.CreationDate) AS LastPostActivityDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        AVG(CAST(P.Score AS NUMERIC)) AS AvgPostScoreOwned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    WHERE
        U.Reputation > 750
        AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
        AND U.Views > 50
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views
),
PostHistoryMetrics AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS FirstClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeletedEver,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS WasUndeletedEver,
        STRING_AGG(DISTINCT CLR.Name, '; ') FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS CloseReasonDetails
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CLR ON PH.PostHistoryTypeId = 10 AND CLR.Id = CAST(PH.Comment AS SMALLINT)
    GROUP BY
        PH.PostId
),
RecentHighImpactPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId AS PostOwnerId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.Title AS PostTitle,
        P.Tags AS PostTags,
        'Question' AS PostType,
        P.AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.AcceptedAnswerId,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id) AS CommentCountForPost,
        NULL AS AnswerToQuestionId,
        NULL AS ParentQuestionScore
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1
        AND P.Score > 75
        AND P.AnswerCount > 3
        AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4' YEAR)
    UNION ALL
    SELECT
        A.Id AS PostId,
        A.OwnerUserId AS PostOwnerId,
        A.CreationDate AS PostCreationDate,
        A.Score AS PostScore,
        NULL AS PostViewCount,
        NULL AS PostTitle,
        NULL AS PostTags,
        'Answer' AS PostType,
        NULL AS AnswerCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = A.Id AND V.VoteTypeId = 5) AS FavoriteCount,
        A.ParentId AS AcceptedAnswerId,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = A.Id) AS CommentCountForPost,
        A.ParentId AS AnswerToQuestionId,
        Q.Score AS ParentQuestionScore
    FROM
        Posts A
    INNER JOIN
        Posts Q ON A.ParentId = Q.Id
    WHERE
        A.PostTypeId = 2
        AND A.Score > 40
        AND Q.ViewCount > 25000
        AND A.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4' YEAR)
)
SELECT
    UE.UserId,
    UE.UserDisplayName,
    UE.Reputation,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.AvgPostScoreOwned,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.LastPostActivityDate,
    RHIP.PostId,
    RHIP.PostType,
    RHIP.PostTitle,
    RHIP.PostScore AS CurrentPostScore,
    RHIP.PostViewCount,
    RHIP.PostCreationDate,
    RHIP.AnswerCount AS QuestionAnswerCount,
    RHIP.FavoriteCount AS PostFavoriteCount,
    RHIP.CommentCountForPost,
    COALESCE(PHM.TotalHistoryEntries, 0) AS PostTotalHistoryEntries,
    COALESCE(PHM.EditCount, 0) AS PostEditCount,
    PHM.LastHistoryDate AS PostLastEditDate,
    PHM.FirstClosedDate,
    PHM.LastReopenedDate,
    PHM.WasDeletedEver,
    PHM.WasUndeletedEver,
    PHM.CloseReasonDetails,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostScore DESC, RHIP.PostCreationDate DESC) AS UserPostRankByScore,
    LEAD(RHIP.PostCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate) AS NextPostCreationDate,
    LAG(RHIP.PostCreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate) AS PreviousPostCreationDate,
    DATE_PART('day', RHIP.PostCreationDate - LAG(RHIP.PostCreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY RHIP.PostCreationDate)) AS DaysSincePrevPost,
    STRING_AGG(DISTINCT PostTag.TagName, ', ') FILTER (WHERE PostTag.TagName IS NOT NULL) AS AssociatedTags,
    (
        SELECT
            COUNT(DISTINCT PL.RelatedPostId)
        FROM
            PostLinks PL
        WHERE
            PL.PostId = RHIP.PostId
            AND PL.LinkTypeId = 3
    ) AS DuplicateCount,
    NULLIF(RHIP.PostScore, 0) / NULLIF(RHIP.PostViewCount, 0) AS ScorePerViewRatio,
    CASE
        WHEN RHIP.PostType = 'Question' AND RHIP.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answered Question'
        WHEN RHIP.PostType = 'Question' AND PHM.FirstClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN RHIP.PostType = 'Answer' AND RHIP.PostScore > 100 THEN 'Highly Voted Answer'
        WHEN RHIP.PostType = 'Answer' AND RHIP.ParentQuestionScore > 200 THEN 'Answer To Very Popular Question'
        ELSE 'Other High Impact Post'
    END AS PostStatusCategory,
    DATE_PART('day', CAST('2024-10-01 12:34:56' AS TIMESTAMP) - RHIP.PostCreationDate) AS DaysSincePostCreation,
    COALESCE(U.Location, 'Unknown') AS UserLocation_COALESCE,
    NULLIF(UE.TotalQuestionsOwned + UE.TotalAnswersOwned, 0) AS TotalContributionsForUser
FROM
    UserEngagement UE
INNER JOIN
    RecentHighImpactPosts RHIP ON UE.UserId = RHIP.PostOwnerId
LEFT JOIN
    PostHistoryMetrics PHM ON RHIP.PostId = PHM.PostId
LEFT JOIN LATERAL
    (SELECT value AS TagName FROM (VALUES (NULL)) v(value)) AS PostTagDummy ON FALSE
LEFT JOIN LATERAL
    (
        SELECT TRIM(BOTH '<>' FROM part) AS TagName
        FROM (
            SELECT UNNEST(REGEXP_SPLIT_TO_ARRAY(COALESCE(RHIP.PostTags, ''), '><')) AS part
        ) s
    ) PostTag ON TRUE
LEFT JOIN
    Tags T ON LOWER(PostTag.TagName) = LOWER(T.TagName)
LEFT JOIN
    Users U ON UE.UserId = U.Id
WHERE
    (PHM.WasDeletedEver = 0 OR PHM.WasDeletedEver IS NULL)
    AND RHIP.PostScore >= (
        SELECT AVG(rhp.PostScore) FROM RecentHighImpactPosts rhp WHERE rhp.PostType = RHIP.PostType
    ) * 1.25
    AND UE.TotalPostsOwned > 5
    AND (RHIP.PostTitle IS NOT NULL OR RHIP.PostType = 'Answer')
    AND RHIP.PostCreationDate BETWEEN UE.UserCreationDate AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)
    AND (PHM.FirstClosedDate IS NULL OR PHM.LastReopenedDate IS NOT NULL)
GROUP BY
    UE.UserId,
    UE.UserDisplayName,
    UE.Reputation,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.AvgPostScoreOwned,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.LastPostActivityDate,
    RHIP.PostId,
    RHIP.PostType,
    RHIP.PostTitle,
    RHIP.PostScore,
    RHIP.PostViewCount,
    RHIP.PostCreationDate,
    RHIP.AnswerCount,
    RHIP.FavoriteCount,
    RHIP.CommentCountForPost,
    PHM.TotalHistoryEntries,
    PHM.EditCount,
    PHM.LastHistoryDate,
    PHM.FirstClosedDate,
    PHM.LastReopenedDate,
    PHM.WasDeletedEver,
    PHM.WasUndeletedEver,
    PHM.CloseReasonDetails,
    RHIP.AcceptedAnswerId,
    UE.UserCreationDate,
    U.Location,
    RHIP.ParentQuestionScore
ORDER BY
    UE.Reputation DESC,
    UE.UserId,
    UserPostRankByScore DESC;