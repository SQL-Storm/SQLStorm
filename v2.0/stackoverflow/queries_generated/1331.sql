-- {"query": "1331.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2577} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.Score, 0)) AS TotalAuthoredPostScore,
        COUNT(DISTINCT B.Id) AS TotalBadgesReceived,
        MAX(U.LastAccessDate) AS LatestUserActivity,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScoreAuthored,
        (
            SELECT TOP 1 TRIM(TagSplit.value)
            FROM PostHistory PH_Tags
            CROSS APPLY STRING_SPLIT(SUBSTRING(PH_Tags.Text, 2, LEN(PH_Tags.Text) - 2), '><') AS TagSplit
            WHERE PH_Tags.PostId IN (SELECT P_Inner.Id FROM Posts P_Inner WHERE P_Inner.OwnerUserId = U.Id)
              AND PH_Tags.PostHistoryTypeId = 3 -- Initial Tags
              AND PH_Tags.Text IS NOT NULL AND LEN(PH_Tags.Text) > 2
            GROUP BY TRIM(TagSplit.value)
            ORDER BY COUNT(*) DESC, TRIM(TagSplit.value) ASC
        ) AS MostFrequentInitialTagByAuthor
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ViewCount,
        P.Score AS PostScore,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount AS ReportedAnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        CR.Name AS CloseReason,
        COUNT(DISTINCT PH_EditBody.Id) AS BodyEditCount,
        COUNT(DISTINCT PH_EditTags.Id) AS TagEditCount,
        MAX(CASE WHEN PH_Closed.PostHistoryTypeId = 10 THEN PH_Closed.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH_Reopened.PostHistoryTypeId = 11 THEN PH_Reopened.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(PH_MigrationAway.CreationDate) AS LastMigratedAwayDate
    FROM Posts P
    LEFT JOIN PostHistory PH_Closed ON P.Id = PH_Closed.PostId AND PH_Closed.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON TRY_CAST(PH_Closed.Comment AS INT) = CR.Id
    LEFT JOIN PostHistory PH_Reopened ON P.Id = PH_Reopened.PostId AND PH_Reopened.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_EditBody ON P.Id = PH_EditBody.PostId AND PH_EditBody.PostHistoryTypeId = 5
    LEFT JOIN PostHistory PH_EditTags ON P.Id = PH_EditTags.PostId AND PH_EditTags.PostHistoryTypeId = 6
    LEFT JOIN PostHistory PH_MigrationAway ON P.Id = PH_MigrationAway.PostId AND PH_MigrationAway.PostHistoryTypeId = 35
    WHERE P.PostTypeId = 1 -- Only Questions
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.ViewCount, P.Score, P.OwnerUserId, P.Title, P.Tags, P.AnswerCount, P.FavoriteCount, P.ClosedDate, CR.Name
),
AnswerAndCommentAggregates AS (
    SELECT
        Q.Id AS QuestionId,
        COUNT(DISTINCT A.Id) AS ActualAnswerCount,
        AVG(COALESCE(A.Score, 0)) AS AvgAnswerScore,
        SUM(COALESCE(A.CommentCount, 0)) AS TotalCommentsOnAnswers,
        AVG(COALESCE(C.Score, 0)) AS AvgCommentScoreOnQuestion,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnQuestion,
        MAX(A.CreationDate) AS LatestAnswerDate,
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to the Question
    LEFT JOIN Comments C ON Q.Id = C.PostId -- Comments directly on the Question
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id
),
PostLinkSummary AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS NumberOfLinkedPosts,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS NumberOfDuplicatePosts,
        MAX(PL_Linked.CreationDate) AS LatestLinkedPostDate,
        MAX(PL_Duplicate.CreationDate) AS LatestDuplicatePostDate
    FROM Posts P
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    WHERE P.PostTypeId = 1
    GROUP BY P.Id
),
PrimaryPostTags AS (
    SELECT
        PostId,
        TRIM(value) AS PrimaryTag,
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY LEN(TRIM(value)) DESC, TRIM(value) ASC) AS rn
    FROM Posts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><')
    WHERE Tags IS NOT NULL AND LEN(Tags) > 2 AND PostTypeId = 1
),
RankedPopularTags AS (
    SELECT
        TRIM(value) AS TagName,
        COUNT(P.Id) AS TaggedPostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC, TRIM(value) ASC) AS GlobalTagRank
    FROM Posts P
    CROSS APPLY STRING_SPLIT(SUBSTRING(P.Tags, 2, LEN(P.Tags) - 2), '><')
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LEN(P.Tags) > 2
    GROUP BY TRIM(value)
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    PHM.PostId,
    PHM.Title AS QuestionTitle,
    PHM.PostCreationDate,
    DATEDIFF(day, PHM.PostCreationDate, PHM.LastActivityDate) AS DaysSinceCreationActivity,
    COALESCE(PHM.ViewCount, 0) AS ViewCount,
    PHM.PostScore,
    COALESCE(PHM.FavoriteCount, 0) AS FavoriteCount,
    PHM.ReportedAnswerCount AS InitialReportedAnswerCount,
    COALESCE(ACA.ActualAnswerCount, 0) AS CurrentActualAnswerCount,
    ACA.AvgAnswerScore,
    COALESCE(ACA.TotalCommentsOnQuestion, 0) AS TotalCommentsOnQuestion,
    ACA.AvgCommentScoreOnQuestion,
    COALESCE(PLS.NumberOfLinkedPosts, 0) AS NumberOfLinkedQuestions,
    COALESCE(PLS.NumberOfDuplicatePosts, 0) AS NumberOfDuplicateQuestions,
    PHM.BodyEditCount,
    PHM.TagEditCount,
    PHM.CloseReason,
    CASE
        WHEN PHM.LastMigratedAwayDate IS NOT NULL THEN 'Migrated Away'
        WHEN PHM.ClosedDate IS NOT NULL OR PHM.LastClosedDate IS NOT NULL THEN
            CASE
                WHEN PHM.LastReopenedDate IS NOT NULL AND PHM.LastReopenedDate > COALESCE(PHM.ClosedDate, PHM.LastClosedDate) THEN 'Reopened'
                ELSE 'Closed'
            END
        ELSE 'Open'
    END AS PostLifecycleStatus,
    LAG(PHM.PostScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY PHM.PostCreationDate) AS PreviousPostScoreByAuthor,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY PHM.PostScore DESC, PHM.PostCreationDate ASC) AS UserQuestionScoreRank,
    COALESCE(UE.MostFrequentInitialTagByAuthor, '(No Primary Tag Data)') AS UserPreferredTagCategory,
    RPT.GlobalTagRank AS QuestionPrimaryTagGlobalRank,
    (
        SELECT COUNT(DISTINCT V.Id)
        FROM Votes V
        WHERE V.PostId = PHM.PostId AND V.VoteTypeId = 2 -- UpMod (Upvote)
    ) AS UpVoteCountForQuestion, -- Correlated subquery for a specific vote type
    NULLIF(CAST(PHM.ViewCount AS NUMERIC(10,2)), 0) / NULLIF(CAST(PHM.PostScore AS NUMERIC(10,2)), 0) AS ViewScoreRatio, -- Complicated calculation with NULLIF and explicit casting
    IIF(PHM.LastClosedDate IS NOT NULL AND DATEDIFF(hour, PHM.LastClosedDate, GETDATE()) < 24, 'Recently Closed', 'Not Recently Closed') AS RecentClosureFlag -- Conditional expression
FROM UserEngagement UE
INNER JOIN PostHistoricalMetrics PHM ON UE.UserId = PHM.OwnerUserId
LEFT JOIN AnswerAndCommentAggregates ACA ON PHM.PostId = ACA.QuestionId
LEFT JOIN PostLinkSummary PLS ON PHM.PostId = PLS.PostId
LEFT JOIN PrimaryPostTags PPT ON PHM.PostId = PPT.PostId AND PPT.rn = 1
LEFT JOIN RankedPopularTags RPT ON PPT.PrimaryTag = RPT.TagName
WHERE
    UE.Reputation > 5000 -- Filter for influential users
    AND PHM.ViewCount > 1000 -- Only highly viewed questions
    AND PHM.PostScore > 50 -- Only highly rated questions
    AND PHM.PostCreationDate >= DATEADD(month, -18, GETDATE()) -- Questions from the last 18 months
    AND (
        PHM.Title LIKE '%performance%' OR
        PHM.Title LIKE '%benchmark%' OR
        PHM.Body LIKE '%performance%' OR -- Search in body for additional complexity
        PHM.Tags LIKE '%<sql-server>%' OR
        PHM.Tags LIKE '%<optimization>%' OR
        PHM.Tags LIKE '%<database-design>%'
    )
ORDER BY
    UE.Reputation DESC,
    PHM.PostScore DESC,
    DaysSinceCreationActivity ASC,
    PHM.LastActivityDate DESC
OFFSET 0 ROWS FETCH NEXT 2000 ROWS ONLY;
