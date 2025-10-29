WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgeCount,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgeCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        SUM(COALESCE(P.Score, 0)) AS LifetimePostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS LifetimeQuestionViews
    FROM
        Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.Reputation > 7500
        AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
        AND U.DisplayName IS NOT NULL
        AND U.Location IS NOT NULL
        AND U.Location NOT IN ('', '(null)', 'unknown')
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.LastAccessDate, U.CreationDate
    HAVING
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) >= 1
        OR SUM(COALESCE(P.Score, 0)) > 2500
),
PostHistoryAggregates AS (
    WITH HistoryDetails AS (
        SELECT
            PH.PostId,
            PH.PostHistoryTypeId,
            PH.CreationDate AS HistoryDate,
            LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryDate,
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) / 3600.0 AS TimeSinceLastHistoryHours
        FROM
            PostHistory PH
        WHERE
            PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
            AND PH.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year')
    )
    SELECT
        HD.PostId,
        MAX(CASE WHEN HD.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasEverClosedFlag,
        COUNT(DISTINCT CASE WHEN HD.PostHistoryTypeId IN (4, 5, 6) THEN HD.HistoryDate END) AS TotalUniqueEditEvents,
        AVG(HD.TimeSinceLastHistoryHours) FILTER (WHERE HD.TimeSinceLastHistoryHours > 0) AS AvgHoursBetweenHistoryEvents,
        MAX(HD.TimeSinceLastHistoryHours) FILTER (WHERE HD.TimeSinceLastHistoryHours > 0) AS MaxHoursBetweenHistoryEvents
    FROM
        HistoryDetails HD
    GROUP BY
        HD.PostId
),
QuestionDetailsExtended AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate,
        Q.ClosedDate,
        Q.Tags,
        COALESCE(A.Id, -1) AS AcceptedAnswerPostId,
        COALESCE(A.Score, 0) AS AcceptedAnswerScore,
        COALESCE(MAX_A.MaxAnswerScore, 0) AS HighestAnswerScore,
        COALESCE(T.TagName, 'Untagged') AS PrimaryTagName,
        CASE
            WHEN Q.Tags IS NULL OR LENGTH(Q.Tags) < 2 THEN 0
            ELSE (
                -- standard SQL: split tags by '><' by removing leading '<' and trailing '>' then splitting on '><'
                SELECT COUNT(*)
                FROM (
                    SELECT TRIM(value) AS tag
                    FROM (
                        SELECT UNNEST(string_to_array(SUBSTRING(Q.Tags FROM 2 FOR LENGTH(Q.Tags) - 2), '><')) AS value
                    ) s1
                ) s2
            )
        END AS NumberOfTags,
        Q.FavoriteCount,
        Q.CommentCount
    FROM
        Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id
    LEFT JOIN (
        SELECT P_ANS.ParentId, MAX(P_ANS.Score) AS MaxAnswerScore
        FROM Posts P_ANS
        WHERE P_ANS.PostTypeId = 2
        GROUP BY P_ANS.ParentId
    ) MAX_A ON Q.Id = MAX_A.ParentId
    LEFT JOIN Tags T ON Q.Tags LIKE '%' || '<' || T.TagName || '>' || '%' AND T.Id = (
        SELECT MIN(T2.Id)
        FROM Tags T2
        WHERE Q.Tags LIKE '%' || '<' || T2.TagName || '>' || '%'
        FETCH FIRST 1 ROW ONLY
    )
    WHERE
        Q.PostTypeId = 1
        AND Q.Score >= 20
        AND Q.ViewCount > 500
        AND Q.OwnerUserId IS NOT NULL
        AND Q.Title IS NOT NULL
),
HighlyEngagedComments AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnQuestion,
        SUM(C.Score) AS SumCommentScores,
        STRING_AGG(CASE WHEN C.Score > 5 THEN SUBSTR(C.Text, 1, 75) ELSE NULL END, ' || ') FILTER (WHERE C.Score > 5) AS TopPositiveCommentSnippets,
        STRING_AGG(CASE WHEN C.Score < -2 THEN SUBSTR(C.Text, 1, 75) ELSE NULL END, ' || ') FILTER (WHERE C.Score < -2) AS TopNegativeCommentSnippets
    FROM
        Comments C
    WHERE
        C.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY
        C.PostId
    HAVING
        COUNT(C.Id) >= 5
        AND (SUM(C.Score) > 10 OR SUM(C.Score) < -5)
),
PostLinkAnalysis AS (
    SELECT
        PL.PostId,
        COUNT(PL.RelatedPostId) AS NumberOfDuplicateLinks,
        STRING_AGG(CAST(PL.RelatedPostId AS VARCHAR), ', ') AS DuplicateRelatedPostIds
    FROM
        PostLinks PL
    WHERE
        PL.LinkTypeId = 3
    GROUP BY
        PL.PostId
)
SELECT
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.GoldBadgeCount,
    UE.SilverBadgeCount,
    QDE.QuestionTitle,
    QDE.QuestionScore,
    QDE.ViewCount AS QuestionViewCount,
    QDE.HighestAnswerScore,
    QDE.AcceptedAnswerScore,
    QDE.PrimaryTagName,
    QDE.NumberOfTags,
    (QDE.ClosedDate IS NOT NULL) AS IsQuestionClosed,
    COALESCE(PHA.WasEverClosedFlag, 0) AS WasEverClosedByHistory,
    COALESCE(PHA.TotalUniqueEditEvents, 0) AS TotalEditHistoryEvents,
    PHA.AvgHoursBetweenHistoryEvents,
    PHA.MaxHoursBetweenHistoryEvents,
    COALESCE(HEC.TotalCommentsOnQuestion, 0) AS QuestionCommentCount,
    COALESCE(HEC.SumCommentScores, 0) AS QuestionCommentsTotalScore,
    HEC.TopPositiveCommentSnippets,
    HEC.TopNegativeCommentSnippets,
    COALESCE(PLA.NumberOfDuplicateLinks, 0) AS HasDuplicateLinks,
    PLA.DuplicateRelatedPostIds,
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = QDE.QuestionId AND V.VoteTypeId = 2 AND V.UserId = UE.UserId AND V.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')) AS UserUpvotesOnOwnQuestionRecent,
    (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = QDE.QuestionId AND V.VoteTypeId = 8 AND V.BountyAmount > 0) AS TotalBountyOnQuestion,
    CASE
        WHEN QDE.ClosedDate IS NOT NULL AND COALESCE(QDE.HighestAnswerScore, 0) < 10 THEN 'Closed_UnsatisfactoryAnswers'
        WHEN QDE.ClosedDate IS NOT NULL THEN 'Closed_WithAnswers'
        WHEN QDE.QuestionScore >= 500 AND COALESCE(QDE.HighestAnswerScore, 0) >= 100 AND QDE.FavoriteCount > 20 THEN 'Highly_Successful_Engaged'
        WHEN QDE.QuestionScore >= 200 AND QDE.NumberOfTags >= 5 AND QDE.ViewCount > 5000 THEN 'Popular_BroadTopic_HighTraffic'
        ELSE 'Other'
    END AS QuestionSuccessCategory,
    CASE
        WHEN QDE.QuestionCreationDate IS NOT NULL AND QDE.LastActivityDate IS NOT NULL
             AND (QDE.LastActivityDate - QDE.QuestionCreationDate) > INTERVAL '1 year'
             AND LENGTH(QDE.QuestionTitle) > 75
             AND QDE.CommentCount > 10 THEN 'LongLived_Verbose_Discussed'
        WHEN QDE.QuestionCreationDate IS NOT NULL AND QDE.LastActivityDate IS NOT NULL
             AND (QDE.LastActivityDate - QDE.QuestionCreationDate) < INTERVAL '30 days'
             AND COALESCE(QDE.QuestionScore, 0) < 5
             AND COALESCE(QDE.ViewCount, 0) < 100 THEN 'Recent_LowImpact'
        ELSE NULL
    END AS QuestionLifecyclePattern,
    COALESCE(
        (SELECT U_AA.DisplayName FROM Users U_AA WHERE U_AA.Id = (
            SELECT P_AA.OwnerUserId FROM Posts P_AA WHERE P_AA.Id = QDE.AcceptedAnswerPostId AND P_AA.OwnerUserId IS NOT NULL
            FETCH FIRST 1 ROW ONLY
        ) FETCH FIRST 1 ROW ONLY),
        'N/A'
    ) AS AcceptedAnswerOwnerDisplayName
FROM
    UserEngagement UE
INNER JOIN
    QuestionDetailsExtended QDE ON UE.UserId = QDE.QuestionOwnerId
LEFT JOIN
    PostHistoryAggregates PHA ON QDE.QuestionId = PHA.PostId
LEFT JOIN
    HighlyEngagedComments HEC ON QDE.QuestionId = HEC.PostId
LEFT JOIN
    PostLinkAnalysis PLA ON QDE.QuestionId = PLA.PostId
WHERE
    QDE.HighestAnswerScore > 0
    AND (QDE.QuestionTitle LIKE '%performance%' OR QDE.Tags LIKE '%<sql>%' OR QDE.PrimaryTagName IN ('optimization', 'database-performance'))
    AND (UE.TotalQuestionsPosted + UE.TotalAnswersPosted) > 10
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_CLOSE
        LEFT JOIN Comments C_NEG ON PH_CLOSE.PostId = C_NEG.PostId
        WHERE PH_CLOSE.PostId = QDE.QuestionId
          AND PH_CLOSE.PostHistoryTypeId = 10
          AND (PH_CLOSE.CreationDate - QDE.QuestionCreationDate) < INTERVAL '7 days'
          AND C_NEG.Score < 0 AND LOWER(C_NEG.Text) LIKE '%confusing%'
    )
GROUP BY
    UE.DisplayName, UE.Reputation, UE.GoldBadgeCount, UE.SilverBadgeCount,
    QDE.QuestionTitle, QDE.QuestionScore, QDE.ViewCount, QDE.HighestAnswerScore, QDE.AcceptedAnswerScore,
    QDE.PrimaryTagName, QDE.NumberOfTags, QDE.ClosedDate, QDE.QuestionId, UE.UserId,
    PHA.WasEverClosedFlag, PHA.TotalUniqueEditEvents, PHA.AvgHoursBetweenHistoryEvents, PHA.MaxHoursBetweenHistoryEvents,
    HEC.TotalCommentsOnQuestion, HEC.SumCommentScores, HEC.TopPositiveCommentSnippets, HEC.TopNegativeCommentSnippets,
    PLA.NumberOfDuplicateLinks, PLA.DuplicateRelatedPostIds, QDE.AcceptedAnswerPostId, QDE.FavoriteCount,
    QDE.CommentCount, QDE.QuestionCreationDate, QDE.LastActivityDate, UE.LastAccessDate, UE.UserCreationDate, QDE.Tags
ORDER BY
    UE.Reputation DESC, QDE.QuestionScore DESC, QDE.LastActivityDate DESC
FETCH FIRST 500 ROWS ONLY;