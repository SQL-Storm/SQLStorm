-- {"query": "1744.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3642}
WITH UserRelevantPosts AS (
    SELECT
        P.Id AS EntityId,
        P.PostTypeId,
        P.OwnerUserId AS UserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        P.CommentCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Body,
        P.Title,
        'Post' AS ActivityType,
        CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
      AND (P.PostTypeId = 1 OR P.PostTypeId = 2)
      AND P.Body IS NOT NULL AND LENGTH(P.Body) > 50
    UNION ALL
    SELECT
        C.Id AS EntityId,
        99 AS PostTypeId,
        C.UserId,
        C.CreationDate,
        C.Score,
        NULL AS ViewCount,
        NULL AS AcceptedAnswerId,
        C.PostId AS ParentId,
        NULL AS Tags,
        NULL AS CommentCount,
        C.CreationDate AS LastActivityDate,
        NULL AS ClosedDate,
        C.Text AS Body,
        NULL AS Title,
        'Comment' AS ActivityType,
        FALSE AS IsCommunityOwned
    FROM Comments C
    WHERE C.UserId IS NOT NULL
      AND C.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
      AND LENGTH(C.Text) > 20
),
UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 THEN URP.EntityId END) AS QuestionsAsked,
        SUM(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 AND URP.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.EntityId END) AS AnswersGiven,
        SUM(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 2 THEN URP.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Comment' THEN URP.EntityId END) AS TotalCommentsMade,
        MAX(URP.LastActivityDate) AS LastUserOverallActivityDate
    FROM Users U
    INNER JOIN UserRelevantPosts URP ON U.Id = URP.UserId
    WHERE U.Reputation > 5000
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT CASE WHEN URP.ActivityType = 'Post' AND URP.PostTypeId = 1 THEN URP.EntityId END) >= 1
),
UserOwnPostEditHistory AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS OwnPostsEditedCount,
        MAX(PH.CreationDate) AS LastOwnPostEditDate,
        (EXTRACT(EPOCH FROM (MAX(PH.CreationDate) - MIN(PH.CreationDate))) / (60 * 60 * 24)) AS DaysBetweenFirstAndLastEdit
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId = P.OwnerUserId
      AND PH.PostHistoryTypeId IN (4,5,6)
      AND PH.UserId <> -1
      AND PH.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
    GROUP BY PH.UserId
    HAVING COUNT(DISTINCT PH.PostId) >= 1
),
UserBadgeTimeSpans AS (
    SELECT
        B.UserId,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate,
        (EXTRACT(EPOCH FROM (MAX(B.Date) - MIN(B.Date))) / (60 * 60 * 24)) AS DaysSpanBetweenBadges
    FROM Badges B
    WHERE B.Class IN (1,2)
      AND B.Date BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
    GROUP BY B.UserId
    HAVING COUNT(B.Id) >= 2
),
UserUpvotedOtherAnswers AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT A.Id) AS UpvotedOtherAnswersCount
    FROM Posts A
    INNER JOIN Posts Q ON A.ParentId = Q.Id AND A.OwnerUserId <> Q.OwnerUserId
    INNER JOIN Votes V ON A.Id = V.PostId
    WHERE A.PostTypeId = 2
      AND V.VoteTypeId = 2
      AND A.CreationDate > (DATE '2024-10-01' - INTERVAL '3 year')
    GROUP BY A.OwnerUserId
    HAVING COUNT(DISTINCT A.Id) >= 1
),
UserRankedPosts AS (
    SELECT
        URP.UserId,
        URP.EntityId AS PostId,
        URP.PostTypeId,
        URP.CreationDate AS PostCreationDate,
        URP.Score AS PostScore,
        URP.ViewCount,
        URP.Tags,
        URP.CommentCount,
        URP.LastActivityDate,
        URP.Title,
        ROW_NUMBER() OVER (PARTITION BY URP.UserId ORDER BY URP.LastActivityDate DESC, URP.Score DESC) AS rn_post_activity,
        LAG(URP.Score, 1, 0) OVER (PARTITION BY URP.UserId ORDER BY URP.CreationDate) AS PreviousPostScore,
        COALESCE(URP.ClosedDate, TIMESTAMP '9999-12-31 23:59:59') AS EffectiveClosedDate
    FROM UserRelevantPosts URP
    WHERE URP.ActivityType = 'Post' AND COALESCE(URP.ViewCount,0) > 10 AND URP.Body IS NOT NULL
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsAsked,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.AnswersGiven,
    UAS.TotalAnswerScore,
    UAS.AvgAnswerScore,
    UAS.TotalCommentsMade,
    UOEH.OwnPostsEditedCount,
    UOEH.LastOwnPostEditDate,
    UOEH.DaysBetweenFirstAndLastEdit,
    UBTS.DaysSpanBetweenBadges,
    UUOA.UpvotedOtherAnswersCount,
    (
        SELECT T.TagName
        FROM Posts P_sub,
             LATERAL (
                 SELECT UNNEST(
                     CASE
                         WHEN P_sub.Tags IS NULL THEN ARRAY[]::text[] -- keep for dialects that support ARRAY[]; will be treated as empty
                         ELSE string_to_array(SUBSTRING(P_sub.Tags FROM 2 FOR LENGTH(P_sub.Tags) - 2), '><')
                     END
                 ) AS tag_name_parsed
             ) AS unnested
        JOIN Tags T ON T.TagName = unnested.tag_name_parsed
        WHERE P_sub.OwnerUserId = UAS.UserId
          AND P_sub.PostTypeId = 1
          AND P_sub.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
        GROUP BY T.TagName
        ORDER BY COUNT(P_sub.Id) DESC, SUM(P_sub.Score) DESC, T.TagName ASC
        LIMIT 1
    ) AS MostActiveQuestionTag,
    STRING_AGG(URP.Title || ' (Score: ' || COALESCE(URP.PostScore,0) || ')', '; ' ORDER BY URP.rn_post_activity) AS Top3RecentPostsTitles,
    SUM(CASE WHEN URP.PostTypeId = 1 AND COALESCE(URP.PostScore,0) > COALESCE(URP.PreviousPostScore,0) THEN 1 ELSE 0 END) AS QuestionsWithScoreIncrease,
    CASE
        WHEN UAS.Reputation >= 200000 THEN 'Legendary Contributor'
        WHEN UAS.Reputation >= 50000 THEN 'Senior Contributor'
        WHEN UAS.Reputation >= 10000 THEN 'Mid-Level Contributor'
        ELSE 'Junior Contributor'
    END AS UserTier,
    COALESCE(MAX(CASE WHEN PH_Closed.PostHistoryTypeId = 10 AND PH_Closed.Comment LIKE '101%' THEN PH_Closed.CreationDate END), TIMESTAMP '1900-01-01 00:00:00') AS LastDuplicateClosureDateForOwnPosts,
    (
        SELECT MAX(V.CreationDate)
        FROM Votes V
        WHERE V.UserId = UAS.UserId
          AND V.VoteTypeId = 5
          AND V.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
    ) AS LastFavoriteVoteDate,
    (UAS.Reputation / 1000.0) * 0.3 + (UAS.QuestionsAsked * 2.0) * 0.2 + (UAS.AnswersGiven * 1.5) * 0.15 + (UAS.TotalCommentsMade * 0.5) * 0.1 + (COALESCE(UOEH.OwnPostsEditedCount, 0) * 1.0) * 0.1
    + (COALESCE(UBTS.DaysSpanBetweenBadges, 0) / 365.0) * 0.05 + (COALESCE(UUOA.UpvotedOtherAnswersCount, 0) * 1.0) * 0.1 AS CompositeActivityScore,
    UAS.LastUserOverallActivityDate
FROM UserActivitySummary UAS
LEFT JOIN UserOwnPostEditHistory UOEH ON UAS.UserId = UOEH.UserId
LEFT JOIN UserBadgeTimeSpans UBTS ON UAS.UserId = UBTS.UserId
INNER JOIN UserUpvotedOtherAnswers UUOA ON UAS.UserId = UUOA.UserId
LEFT JOIN UserRankedPosts URP ON UAS.UserId = URP.UserId AND URP.rn_post_activity <= 3
LEFT JOIN PostHistory PH_Closed ON UAS.UserId = PH_Closed.UserId
    AND PH_Closed.PostId IN (SELECT EntityId FROM UserRelevantPosts WHERE UserId = UAS.UserId AND ActivityType = 'Post' AND PostTypeId = 1)
    AND PH_Closed.PostHistoryTypeId = 10
    AND PH_Closed.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
WHERE UAS.QuestionsWithAcceptedAnswer >= 1
  AND UAS.TotalCommentsMade >= 5
  AND UOEH.OwnPostsEditedCount >= 1
  AND UBTS.DaysSpanBetweenBadges IS NOT NULL
  AND UUOA.UpvotedOtherAnswersCount >= 1
  AND EXISTS (
        SELECT 1
        FROM UserRelevantPosts URP_crit
        WHERE URP_crit.UserId = UAS.UserId
          AND URP_crit.PostTypeId = 1
          AND COALESCE(URP_crit.CommentCount,0) >= 5
          AND LENGTH(URP_crit.Body) > 500
          AND URP_crit.CreationDate BETWEEN UAS.UserCreationDate AND (UAS.UserCreationDate + INTERVAL '5 year')
          AND NOT (URP_crit.Title ILIKE '%[duplicate]%')
          AND URP_crit.IsCommunityOwned = FALSE
          AND URP_crit.EntityId IN (
                SELECT PL.PostId
                FROM PostLinks PL
                WHERE PL.RelatedPostId = URP_crit.EntityId AND PL.LinkTypeId = 1
            )
    )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.QuestionsAsked,
    UAS.QuestionsWithAcceptedAnswer,
    UAS.AnswersGiven,
    UAS.TotalAnswerScore,
    UAS.AvgAnswerScore,
    UAS.TotalCommentsMade,
    UOEH.OwnPostsEditedCount,
    UOEH.LastOwnPostEditDate,
    UOEH.DaysBetweenFirstAndLastEdit,
    UBTS.DaysSpanBetweenBadges,
    UUOA.UpvotedOtherAnswersCount,
    UAS.LastUserOverallActivityDate
ORDER BY
    CompositeActivityScore DESC,
    UAS.Reputation DESC,
    UBTS.DaysSpanBetweenBadges DESC,
    UAS.LastUserOverallActivityDate DESC
LIMIT 1000;