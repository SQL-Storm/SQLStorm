-- {"query": "1190.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2648} 

WITH UserEngagementStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        AVG(P.ViewCount) AS AvgPostViewCount,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostRevisionDetails AS (
    SELECT
        PH.PostId,
        PH.Id AS HistoryId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryCreationDate,
        PH.UserId AS HistoryUserId,
        PH.Text AS HistoryText,
        LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryText,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS RevisionRank,
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId) AS TotalRevisions
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (2, 5, 8, 4, 6, 9) -- Initial Body, Edit Body, Rollback Body, Edit Title, Edit Tags, Rollback Tags
),
AggregatedPostRevisions AS (
    SELECT
        PostId,
        MAX(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS HasEdit,
        MAX(CASE WHEN PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS HasRollback,
        SUM(CASE WHEN PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
        SUM(CASE WHEN PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEditCount,
        SUM(CASE WHEN PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEditCount,
        AVG(EXTRACT(EPOCH FROM (HistoryCreationDate - PreviousHistoryDate))) FILTER (WHERE RevisionRank > 1) AS AvgSecondsBetweenRevisions,
        AVG(ABS(LENGTH(COALESCE(HistoryText, '')) - LENGTH(COALESCE(PreviousHistoryText, '')))) FILTER (WHERE PostHistoryTypeId IN (2, 5, 8) AND RevisionRank > 1) AS AvgBodyLengthChange
    FROM PostRevisionDetails
    GROUP BY PostId
),
UserTopTags AS (
    SELECT
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY PostsPerTag DESC) AS TopTagsString,
        ARRAY_AGG(TagName ORDER BY PostsPerTag DESC) AS TopTagsArray
    FROM (
        SELECT
            U.Id AS UserId,
            TRIM(unnest(string_to_array(substring(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
            COUNT(P.Id) AS PostsPerTag,
            ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY COUNT(P.Id) DESC) AS TagRank
        FROM Users AS U
        JOIN Posts AS P ON U.Id = P.OwnerUserId
        WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
        GROUP BY U.Id, TagName
    ) AS RankedTags
    WHERE TagRank <= 5
    GROUP BY UserId
),
CommunityPostTags AS (
    SELECT
        P.Id AS PostId,
        STRING_AGG(T.TagName, ', ') AS PostTagString,
        ARRAY_AGG(T.TagName) AS PostTagsArray
    FROM Posts AS P
    JOIN Tags AS T ON P.Id = T.WikiPostId OR P.Id = T.ExcerptPostId
    WHERE P.OwnerUserId = -1
      AND P.PostTypeId IN (4, 5)
    GROUP BY P.Id
)
SELECT
    UES.DisplayName AS UserDisplayName,
    UES.Reputation,
    UES.TotalPosts,
    UES.QuestionsAsked,
    UES.AnswersProvided,
    UES.TotalPostScore,
    COALESCE(APR.HasEdit, 0) AS HasEdit,
    COALESCE(APR.BodyEditCount, 0) AS BodyEditCount,
    APR.AvgSecondsBetweenRevisions,
    APR.AvgBodyLengthChange,
    P.Title AS LatestPostTitle,
    LEFT(COALESCE(P.Body, 'No Body Content'), 500) AS LatestPostBodyExcerpt,
    P.Score AS LatestPostScore,
    P.ViewCount AS LatestPostViewCount,
    P.CommentCount AS LatestPostCommentCount,
    P.CreationDate AS LatestPostCreationDate,
    P.LastActivityDate AS LatestPostActivityDate,
    EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) AS PostActiveDurationSeconds,
    CASE
        WHEN P.Score >= 100 AND P.AnswerCount >= 5 THEN 'Highly Engaged & Popular'
        WHEN P.Score >= 50 THEN 'Popular'
        WHEN COALESCE(APR.BodyEditCount, 0) >= 3 THEN 'Highly Edited'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    (SELECT COUNT(B.Id)
     FROM Badges AS B
     WHERE B.UserId = UES.UserId
       AND B.Class = 1
       AND EXTRACT(YEAR FROM B.Date) = EXTRACT(YEAR FROM P.CreationDate)
       AND B.TagBased IS TRUE
    ) > 0 AS HasGoldTagBadgeInPostYear,
    (SELECT U2.DisplayName
     FROM PostHistory AS PH_inner
     JOIN Users AS U2 ON PH_inner.UserId = U2.Id
     WHERE PH_inner.PostId = P.Id
       AND PH_inner.UserId IS NOT NULL
       AND PH_inner.UserId != P.OwnerUserId
       AND PH_inner.PostHistoryTypeId IN (4,5,6)
     ORDER BY PH_inner.CreationDate DESC
     LIMIT 1
    ) AS LastNonOwnerEditorDisplayName,
    ROW_NUMBER() OVER (ORDER BY UES.TotalPostScore DESC, UES.Reputation DESC) AS UserPostScoreRank,
    AVG(P.Score) OVER (PARTITION BY P.PostTypeId, DATE_TRUNC('year', P.CreationDate)) AS AvgPostTypeScoreThisYear,
    P.Score - AVG(P.Score) OVER (PARTITION BY P.PostTypeId, DATE_TRUNC('year', P.CreationDate)) AS ScoreDeviationFromTypeAvg,
    COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerIdOrDefault,
    UTT.TopTagsString,
    P.Tags AS OriginalTagsString,
    UTT.TopTagsArray AS ParsedTopTagsArray
FROM UserEngagementStats AS UES
JOIN Posts AS P ON UES.UserId = P.OwnerUserId
LEFT JOIN AggregatedPostRevisions AS APR ON P.Id = APR.PostId
LEFT JOIN UserTopTags AS UTT ON UES.UserId = UTT.UserId
WHERE UES.Reputation > 1000
  AND UES.TotalPosts > 10
  AND P.PostTypeId IN (1, 2)
  AND P.CreationDate >= '2020-01-01'
  AND (P.Tags ILIKE '%sql%' OR P.Tags ILIKE '%database%' OR P.Body ILIKE '%performance%' OR P.Title ILIKE '%optimization%')
  AND P.ViewCount > 500
  AND P.Score IS NOT NULL AND P.Score > 0
  AND (P.LastEditorUserId IS NOT NULL OR P.CommunityOwnedDate IS NOT NULL OR P.AcceptedAnswerId IS NOT NULL)
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory AS PH_Excl
        WHERE PH_Excl.PostId = P.Id
          AND PH_Excl.PostHistoryTypeId = 12
    )

UNION ALL

SELECT
    'Community User' AS UserDisplayName,
    0 AS Reputation,
    COUNT(P.Id) AS TotalPosts,
    0 AS QuestionsAsked,
    0 AS AnswersProvided,
    SUM(P.Score) AS TotalPostScore,
    MAX(COALESCE(APR.HasEdit, 0)) AS HasEdit,
    SUM(COALESCE(APR.BodyEditCount, 0)) AS BodyEditCount,
    AVG(APR.AvgSecondsBetweenRevisions) AS AvgSecondsBetweenRevisions,
    AVG(APR.AvgBodyLengthChange) AS AvgBodyLengthChange,
    'N/A (Community Post Title)' AS LatestPostTitle,
    LEFT(COALESCE(MAX(P.Body), 'No Body Content'), 500) AS LatestPostBodyExcerpt,
    SUM(P.Score) AS LatestPostScore,
    SUM(P.ViewCount) AS LatestPostViewCount,
    SUM(P.CommentCount) AS LatestPostCommentCount,
    MIN(P.CreationDate) AS LatestPostCreationDate,
    MAX(P.LastActivityDate) AS LatestPostActivityDate,
    AVG(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate))) AS PostActiveDurationSeconds,
    'Community Managed Content' AS PostEngagementCategory,
    FALSE AS HasGoldTagBadgeInPostYear,
    'N/A (No Specific Editor)' AS LastNonOwnerEditorDisplayName,
    NULL::bigint AS UserPostScoreRank,
    AVG(P.Score) AS AvgPostTypeScoreThisYear,
    NULL::int AS ScoreDeviationFromTypeAvg,
    -1 AS AcceptedAnswerIdOrDefault,
    STRING_AGG(CPT.PostTagString, '; ') AS TopTagsString, -- Aggregates tag strings from multiple community posts
    NULL AS OriginalTagsString,
    ARRAY_AGG(DISTINCT unnest(CPT.PostTagsArray)) AS ParsedTopTagsArray -- Aggregates unique tags into an array
FROM Posts AS P
LEFT JOIN AggregatedPostRevisions AS APR ON P.Id = APR.PostId
LEFT JOIN CommunityPostTags AS CPT ON P.Id = CPT.PostId
WHERE P.OwnerUserId = -1
  AND P.PostTypeId IN (4, 5)
  AND P.CreationDate >= '2020-01-01'
GROUP BY
    1, 2, 4, 5, 11, 19, 20, 21, 25, 26, 27
ORDER BY
    Reputation DESC NULLS LAST, UserPostScoreRank ASC NULLS LAST, TotalPostScore DESC;
