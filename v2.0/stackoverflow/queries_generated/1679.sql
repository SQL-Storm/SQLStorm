-- {"query": "1679.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3183} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(C.Id) AS TotalComments,
        COUNT(V.Id) AS TotalVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        MAX(U.LastAccessDate) AS LastUserActivity,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostLifeCycleEvents AS (
    SELECT
        PH.PostId,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN PH.CreationDate END) AS PostCreationDate,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS FirstCloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate END) AS FirstDeleteDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN PH.CreationDate END) AS LastUndeleteDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseVoteCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenVoteCount,
        MAX(PH_ClosedReason.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.CreationDate = (SELECT MIN(PH2.CreationDate) FROM PostHistory PH2 WHERE PH2.PostId = PH.PostId AND PH2.PostHistoryTypeId = 10)) AS InitialCloseReason
    FROM PostHistory PH
    LEFT JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes PH_ClosedReason ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND PH_ClosedReason.Id = CAST(PH.Comment AS smallint)
    GROUP BY PH.PostId
),
QuestionTagParsing AS (
    SELECT
        P.Id AS PostId,
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
),
AggregatedQuestionTags AS (
    SELECT
        QTP.PostId,
        STRING_AGG(T.TagName, ';') AS AllTags,
        COUNT(DISTINCT T.Id) AS UniqueTagCount,
        SUM(T.Count) AS TotalTagUsageCount
    FROM QuestionTagParsing QTP
    JOIN Tags T ON QTP.TagName = T.TagName
    GROUP BY QTP.PostId
),
PostCommentScores AS (
    SELECT
        C.PostId,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(C.Id) AS CommentCount,
        AVG(LENGTH(C.Text)) AS AvgCommentLength,
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Comments C
    GROUP BY C.PostId
)
SELECT
    P.Id AS QuestionId,
    P.Title AS QuestionTitle,
    P.CreationDate AS QuestionCreationDate,
    P.Score AS QuestionScore,
    P.ViewCount AS QuestionViewCount,
    P.AnswerCount AS QuestionAnswerCount,
    P.FavoriteCount AS QuestionFavoriteCount,
    P.ClosedDate,
    COALESCE(P.ContentLicense, 'Unknown') AS ContentLicense,

    UA.DisplayName AS OwnerDisplayName,
    UA.Reputation AS OwnerReputation,
    UA.TotalPosts AS OwnerTotalPosts,
    UA.TotalBadges AS OwnerTotalBadges,
    COALESCE(LEU.DisplayName, 'Community') AS LastEditorDisplayName,

    PLE.PostCreationDate,
    PLE.FirstEditDate,
    PLE.LastEditDate,
    PLE.FirstCloseDate,
    PLE.LastReopenDate,
    PLE.InitialCloseReason,
    PLE.CloseVoteCount,
    PLE.ReopenVoteCount,

    ACS.TotalCommentScore,
    ACS.CommentCount,
    ACS.AvgCommentLength,
    ACS.LatestCommentDate,

    AQT.AllTags,
    AQT.UniqueTagCount,
    AQT.TotalTagUsageCount,

    -- Calculate Time To First Edit
    EXTRACT(EPOCH FROM (PLE.FirstEditDate - P.CreationDate)) / 3600 AS TimeToFirstEditHours,
    -- Calculate Time To Close (if closed)
    EXTRACT(EPOCH FROM (P.ClosedDate - P.CreationDate)) / 3600 AS TimeToCloseHours,
    -- Time since last activity
    EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / (24 * 3600) AS DaysSinceLastActivity,

    -- Check if the question body contains specific keywords (complicated string search)
    (P.Body LIKE '%SQL%' OR P.Body LIKE '%database%' OR P.Body LIKE '%performance%') AS ContainsDbKeywords,
    -- Check for NULL or short AboutMe in owner profile
    CASE
        WHEN UA.AboutMe IS NULL OR LENGTH(TRIM(UA.AboutMe)) < 50 THEN TRUE
        ELSE FALSE
    END AS OwnerAboutMeSparse,

    -- Correlated Subquery: Get the display name of the user who accepted an answer, if any
    (
        SELECT U_Acceptor.DisplayName
        FROM Users U_Acceptor
        WHERE U_Acceptor.Id = (SELECT PA.OwnerUserId FROM Posts PA WHERE PA.Id = P.AcceptedAnswerId)
    ) AS AcceptedAnswerOwnerDisplayName,

    -- Window Function: Rank questions by score within each owner's questions
    ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate ASC) AS OwnerQuestionScoreRank,
    -- Window Function: Average score of questions for posts created within 3 days of each other, ordered by creation date
    AVG(P.Score) OVER (ORDER BY P.CreationDate RANGE BETWEEN INTERVAL '3 DAY' PRECEDING AND CURRENT ROW) AS RollingAvgScore3Day,

    -- Categorize questions based on their engagement metrics
    CASE
        WHEN P.Score > 100 AND P.AnswerCount > 5 AND P.ViewCount > 5000 THEN 'High Engagement'
        WHEN P.Score > 20 OR P.AnswerCount > 2 OR P.ViewCount > 1000 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementCategory,

    -- NULL Logic: If OwnerDisplayName is NULL (community post), mark as community owned
    COALESCE(UA.DisplayName, 'Community User') AS EffectiveOwnerDisplayName,

    -- Example of complicated numeric calculation with NULL handling
    (P.Score * 0.5 + COALESCE(P.AnswerCount, 0) * 2 + COALESCE(P.FavoriteCount, 0) * 3 + COALESCE(ACS.TotalCommentScore, 0) * 0.1) AS WeightedEngagementScore,

    -- Further analysis for closed questions vs. active questions using UNION ALL
    CASE WHEN P.ClosedDate IS NOT NULL THEN 'Closed Question Analysis' ELSE 'Active Question Analysis' END AS AnalysisType

FROM
    Posts P
LEFT JOIN UserActivitySummary UA ON P.OwnerUserId = UA.UserId
LEFT JOIN Users LEU ON P.LastEditorUserId = LEU.Id
LEFT JOIN PostLifeCycleEvents PLE ON P.Id = PLE.PostId
LEFT JOIN AggregatedQuestionTags AQT ON P.Id = AQT.PostId
LEFT JOIN PostCommentScores ACS ON P.Id = ACS.PostId
WHERE
    P.PostTypeId = 1 -- Only consider questions
    AND P.CreationDate BETWEEN '2019-01-01' AND '2023-01-01' -- Date range for performance
    AND (P.ViewCount > 50 OR P.Score > 5) -- Filter for more relevant posts
    AND (
        (P.ClosedDate IS NOT NULL AND PLE.ReopenVoteCount > 0) OR -- Closed and reopened questions
        (P.ClosedDate IS NULL AND P.FavoriteCount > 0 AND P.AnswerCount > 0) -- Active questions with favorites and answers
    )

UNION ALL

SELECT
    P.Id AS QuestionId,
    P.Title AS QuestionTitle,
    P.CreationDate AS QuestionCreationDate,
    P.Score AS QuestionScore,
    P.ViewCount AS QuestionViewCount,
    P.AnswerCount AS QuestionAnswerCount,
    P.FavoriteCount AS QuestionFavoriteCount,
    P.ClosedDate,
    COALESCE(P.ContentLicense, 'Unknown') AS ContentLicense,

    UA.DisplayName AS OwnerDisplayName,
    UA.Reputation AS OwnerReputation,
    UA.TotalPosts AS OwnerTotalPosts,
    UA.TotalBadges AS OwnerTotalBadges,
    COALESCE(LEU.DisplayName, 'Community') AS LastEditorDisplayName,

    PLE.PostCreationDate,
    PLE.FirstEditDate,
    PLE.LastEditDate,
    PLE.FirstCloseDate,
    PLE.LastReopenDate,
    PLE.InitialCloseReason,
    PLE.CloseVoteCount,
    PLE.ReopenVoteCount,

    ACS.TotalCommentScore,
    ACS.CommentCount,
    ACS.AvgCommentLength,
    ACS.LatestCommentDate,

    AQT.AllTags,
    AQT.UniqueTagCount,
    AQT.TotalTagUsageCount,

    EXTRACT(EPOCH FROM (PLE.FirstEditDate - P.CreationDate)) / 3600 AS TimeToFirstEditHours,
    EXTRACT(EPOCH FROM (P.ClosedDate - P.CreationDate)) / 3600 AS TimeToCloseHours,
    EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / (24 * 3600) AS DaysSinceLastActivity,

    (P.Body LIKE '%Java%' OR P.Body LIKE '%Python%' OR P.Body LIKE '%javascript%') AS ContainsProgrammingKeywords,
    CASE
        WHEN UA.WebsiteUrl IS NULL OR LENGTH(TRIM(UA.WebsiteUrl)) < 10 THEN TRUE
        ELSE FALSE
    END AS OwnerWebsiteMissingOrShort,

    (
        SELECT U_Editor.DisplayName
        FROM Users U_Editor
        WHERE U_Editor.Id = P.LastEditorUserId
    ) AS LastEditorUserDisplayName,

    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC, P.LastActivityDate DESC) AS OwnerQuestionViewRank,
    AVG(P.ViewCount) OVER (ORDER BY P.CreationDate RANGE BETWEEN INTERVAL '7 DAY' PRECEDING AND CURRENT ROW) AS RollingAvgViewCount7Day,

    CASE
        WHEN P.Score < 0 THEN 'Negative Score'
        WHEN P.AnswerCount = 0 THEN 'No Answers'
        ELSE 'Has Answers'
    END AS QuestionStatusCategory,

    COALESCE(U.Location, 'Unspecified Location') AS EffectiveOwnerLocation,

    (P.ViewCount * 0.1 + COALESCE(P.Score, 0) * 1 + COALESCE(P.CommentCount, 0) * 0.5) AS SimplePopularityScore,

    'Answered Question Summary' AS AnalysisType

FROM
    Posts P
INNER JOIN Users U ON P.OwnerUserId = U.Id -- Inner join to ensure valid owner
LEFT JOIN UserActivitySummary UA ON P.OwnerUserId = UA.UserId
LEFT JOIN Users LEU ON P.LastEditorUserId = LEU.Id
LEFT JOIN PostLifeCycleEvents PLE ON P.Id = PLE.PostId
LEFT JOIN AggregatedQuestionTags AQT ON P.Id = AQT.PostId
LEFT JOIN PostCommentScores ACS ON P.Id = ACS.PostId
WHERE
    P.PostTypeId = 1 -- Only questions
    AND P.AnswerCount > 0 -- Questions that have at least one answer
    AND P.LastActivityDate >= '2020-01-01' -- More recent activity
    AND P.Tags LIKE '%<java>%' OR P.Tags LIKE '%<python>%' -- Filter for specific tags to create varied data access patterns

ORDER BY
    QuestionCreationDate DESC, WeightedEngagementScore DESC;