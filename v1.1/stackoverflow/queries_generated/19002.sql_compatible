WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionsPosted,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswersPosted,
        COUNT(P.Id) AS TotalPostsCreated,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostsViewed,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScorePerUser,
        NULLIF(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24), 0) AS DaysActive,
        U.Reputation / NULLIF(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24), 0) AS RepPerDayActive,
        MAX(C.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT B.Name) AS UniqueBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 3 WHEN B.Class = 2 THEN 2 WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BadgeClassScore
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments AS C ON U.Id = C.UserId
    LEFT JOIN
        Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
    HAVING
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) >= 5
        OR U.Reputation >= 10000
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS BodyTagTitleEdits,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (10, 11)) AS CloseReopenEvents,
        MAX(PH.CreationDate) AS LastHistoryDate,
        ARRAY_AGG(DISTINCT PH.UserId) FILTER (WHERE PH.UserId IS NOT NULL AND PH.UserId <> -1) AS DistinctEditorUserIds,
        ARRAY_AGG(DISTINCT CR.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS CloseReasons,
        BOOL_OR(PH.PostHistoryTypeId = 16) AS WasCommunityOwned
    FROM
        PostHistory AS PH
    LEFT JOIN
        CloseReasonTypes AS CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CR.Id AS VARCHAR)
    GROUP BY
        PH.PostId
),
QuestionAnswerSummary AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount AS QuestionViewCount,
        Q.Score AS QuestionScore,
        Q.OwnerUserId AS QuestionOwnerUserId,
        Q.Tags,
        Q.ClosedDate,
        Q.CommunityOwnedDate,
        COUNT(A.Id) AS AnswerCount,
        COALESCE(SUM(A.Score), 0) AS TotalAnswerScore,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(A.CreationDate) AS LastAnswerDate,
        COALESCE(SUM(A.FavoriteCount), 0) AS TotalAnswerFavorites,
        COUNT(DISTINCT A.OwnerUserId) AS UniqueAnswerers,
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = Q.Id AND V.VoteTypeId = 2) AS QuestionUpvoteCount,
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = Q.Id AND V.VoteTypeId = 3) AS QuestionDownvoteCount,
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments AS C WHERE C.PostId = Q.Id AND C.CreationDate BETWEEN Q.CreationDate AND Q.CreationDate + INTERVAL '24 hour') AS EarlyCommentersCount
    FROM
        Posts AS Q
    LEFT JOIN
        Posts AS A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    WHERE
        Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.Title, Q.CreationDate, Q.ViewCount, Q.Score, Q.OwnerUserId, Q.Tags, Q.ClosedDate, Q.CommunityOwnedDate
),
TagPerformanceBreakdown AS (
    SELECT
        QAS.QuestionId,
        QAS.QuestionTitle,
        QAS.QuestionOwnerUserId,
        QAS.AvgAnswerScore,
        TRIM(LOWER(unnest(string_to_array(substring(QAS.Tags, 2, LENGTH(QAS.Tags)-2), '><')))) AS TagName,
        ROW_NUMBER() OVER (PARTITION BY QAS.QuestionOwnerUserId ORDER BY QAS.AvgAnswerScore DESC, QAS.QuestionCreationDate DESC) AS UserQuestionAnswerScoreRank
    FROM
        QuestionAnswerSummary AS QAS
    WHERE
        QAS.Tags IS NOT NULL AND LENGTH(TRIM(QAS.Tags)) > 2
),
LinkedPostInfluence AS (
    SELECT
        PL.PostId,
        P_Related.Id AS RelatedPostId,
        LT.Name AS LinkTypeName,
        P_Related.Score AS RelatedPostScore,
        P_Related.ViewCount AS RelatedPostViewCount,
        U_Related.Reputation AS RelatedPostOwnerReputation,
        U_Related.DisplayName AS RelatedPostOwnerDisplayName,
        AGE(P_Related.CreationDate, P_Linking.CreationDate) AS RelatedPostAgeWhenLinked
    FROM
        PostLinks AS PL
    JOIN
        LinkTypes AS LT ON PL.LinkTypeId = LT.Id
    JOIN
        Posts AS P_Linking ON PL.PostId = P_Linking.Id
    JOIN
        Posts AS P_Related ON PL.RelatedPostId = P_Related.Id
    LEFT JOIN
        Users AS U_Related ON P_Related.OwnerUserId = U_Related.Id
    WHERE
        P_Related.PostTypeId = 2
        AND P_Related.Score > 5
)
SELECT
    'QuestionAnalysis' AS RecordType,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.RepPerDayActive,
    UE.TotalQuestionsPosted,
    UE.TotalAnswersPosted,
    UE.AvgAnswerScorePerUser,
    UE.UniqueBadgesEarned,
    UE.BadgeClassScore,
    QAS.QuestionId,
    QAS.QuestionTitle,
    QAS.QuestionCreationDate,
    QAS.QuestionScore,
    QAS.QuestionViewCount,
    QAS.AnswerCount,
    QAS.TotalAnswerScore,
    QAS.AvgAnswerScore AS QuestionAvgAnswerScore,
    QAS.QuestionUpvoteCount,
    QAS.QuestionDownvoteCount,
    TPB.TagName,
    TPB.UserQuestionAnswerScoreRank,
    COALESCE(PHA.TotalHistoryEvents, 0) AS TotalQuestionHistoryEvents,
    COALESCE(PHA.BodyTagTitleEdits, 0) AS QuestionBodyTagTitleEdits,
    COALESCE(PHA.CloseReopenEvents, 0) AS QuestionCloseReopenEvents,
    PHA.CloseReasons,
    PHA.WasCommunityOwned,
    CASE
        WHEN QAS.ClosedDate IS NOT NULL AND COALESCE(PHA.CloseReopenEvents, 0) > 0 THEN 'Closed & Actively Edited'
        WHEN QAS.ClosedDate IS NOT NULL THEN 'Closed With No Recent Edits'
        WHEN QAS.QuestionViewCount > 5000 AND QAS.AnswerCount = 0 THEN 'High-View Zero-Answer'
        WHEN QAS.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open & Active'
    END AS QuestionStatusCategory,
    COALESCE(BEST_LINK.RelatedPostScore, 0) AS BestLinkedAnswerScore,
    COALESCE(BEST_LINK.RelatedPostOwnerReputation, 0) AS BestLinkedAnswerOwnerReputation,
    COALESCE(BEST_LINK.RelatedPostOwnerDisplayName, 'N/A') AS BestLinkedAnswerOwnerDisplayName,
    (QAS.QuestionUpvoteCount - QAS.QuestionDownvoteCount) AS QuestionNetVotes,
    QAS.EarlyCommentersCount,
    NTILE(5) OVER (ORDER BY UE.Reputation DESC, QAS.AvgAnswerScore DESC, QAS.QuestionViewCount DESC) AS OverallPerformanceQuintile
FROM
    UserEngagement AS UE
INNER JOIN
    QuestionAnswerSummary AS QAS ON UE.UserId = QAS.QuestionOwnerUserId
LEFT JOIN
    PostHistoryAnalysis AS PHA ON QAS.QuestionId = PHA.PostId
LEFT JOIN
    TagPerformanceBreakdown AS TPB ON QAS.QuestionId = TPB.QuestionId
LEFT JOIN LATERAL
    (SELECT
        LPI.RelatedPostScore,
        LPI.RelatedPostOwnerReputation,
        LPI.RelatedPostOwnerDisplayName
    FROM
        LinkedPostInfluence AS LPI
    WHERE
        LPI.PostId = QAS.QuestionId
        AND LPI.LinkTypeName = 'Linked'
    ORDER BY
        LPI.RelatedPostScore DESC, LPI.RelatedPostOwnerReputation DESC
    LIMIT 1) AS BEST_LINK ON TRUE
WHERE
    UE.RepPerDayActive IS NOT NULL AND UE.RepPerDayActive > 5
    AND QAS.QuestionViewCount > 1000
    AND (QAS.TotalAnswerScore >= 100 OR QAS.AnswerCount >= 3)
    AND (QAS.ClosedDate IS NULL OR (QAS.ClosedDate IS NOT NULL AND COALESCE(PHA.CloseReopenEvents, 0) > 1))
    AND TPB.TagName IN ('sql', 'postgresql', 'database', 'performance', 'indexing', 'query-optimization')
    AND LENGTH(QAS.QuestionTitle) BETWEEN 20 AND 120
    AND QAS.QuestionCreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-06-30'
    AND QAS.QuestionScore > 0
    AND QAS.EarlyCommentersCount > 0
UNION ALL
SELECT
    'AnswerAnalysis' AS RecordType,
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    UE_A.RepPerDayActive,
    UE_A.TotalQuestionsPosted,
    UE_A.TotalAnswersPosted,
    A.Score AS AvgAnswerScorePerUser,
    UE_A.UniqueBadgesEarned,
    UE_A.BadgeClassScore,
    Q.Id AS QuestionId,
    Q.Title AS QuestionTitle,
    Q.CreationDate AS QuestionCreationDate,
    Q.Score AS QuestionScore,
    Q.ViewCount AS QuestionViewCount,
    Q.AnswerCount AS QuestionTotalAnswerCount,
    A.Score AS TotalAnswerScore,
    A.Score AS QuestionAvgAnswerScore,
    (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = A.Id AND V.VoteTypeId = 2) AS AnswerUpvoteCount,
    (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = A.Id AND V.VoteTypeId = 3) AS AnswerDownvoteCount,
    TRIM(LOWER(unnest(string_to_array(substring(Q.Tags, 2, LENGTH(Q.Tags)-2), '><')))) AS TagName,
    NULL AS UserQuestionAnswerScoreRank,
    COALESCE(PHA_A.TotalHistoryEvents, 0) AS TotalAnswerHistoryEvents,
    COALESCE(PHA_A.BodyTagTitleEdits, 0) AS AnswerBodyEdits,
    0 AS AnswerCloseReopenEvents,
    NULL AS CloseReasons,
    PHA_A.WasCommunityOwned AS AnswerWasCommunityOwned,
    'High-Value Answer on Moderate Question' AS QuestionStatusCategory,
    0 AS BestLinkedAnswerScore,
    0 AS BestLinkedAnswerOwnerReputation,
    'N/A' AS BestLinkedAnswerOwnerDisplayName,
    ((SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = A.Id AND V.VoteTypeId = 2) - (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = A.Id AND V.VoteTypeId = 3)) AS AnswerNetVotes,
    (SELECT COUNT(DISTINCT C.UserId) FROM Comments AS C WHERE C.PostId = A.Id AND C.CreationDate BETWEEN A.CreationDate AND A.CreationDate + INTERVAL '1 hour') AS EarlyAnswerCommentersCount,
    NTILE(5) OVER (ORDER BY A.Score DESC, U.Reputation DESC, Q.CreationDate ASC) AS OverallPerformanceQuintile
FROM
    Posts AS A
INNER JOIN
    Users AS U ON A.OwnerUserId = U.Id
INNER JOIN
    Posts AS Q ON A.ParentId = Q.Id AND Q.PostTypeId = 1
LEFT JOIN
    UserEngagement AS UE_A ON U.Id = UE_A.UserId
LEFT JOIN
    PostHistoryAnalysis AS PHA_A ON A.Id = PHA_A.PostId
WHERE
    A.PostTypeId = 2
    AND A.Score >= 50
    AND LENGTH(TRIM(A.Body)) > 750
    AND A.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-06-30'
    AND (LOWER(A.Body) LIKE '%performance%' OR LOWER(A.Body) LIKE '%optimization%')
    AND LOWER(A.Body) NOT LIKE '%deprecated%'
    AND U.Reputation BETWEEN 1000 AND 20000
    AND Q.ViewCount < 5000
    AND Q.AnswerCount <= 5
    AND Q.ClosedDate IS NULL
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks AS PL_DUP
        WHERE PL_DUP.PostId = Q.Id AND PL_DUP.LinkTypeId = 3
    )
ORDER BY
    Reputation DESC, AvgAnswerScorePerUser DESC, QuestionCreationDate DESC;