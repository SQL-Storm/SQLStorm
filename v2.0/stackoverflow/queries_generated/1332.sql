-- {"query": "1332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3466} 
WITH UserEngagementSummary AS (
    -- Summarizes user activity, including post and comment counts, reputation, and last activity dates.
    -- Features: LEFT JOIN, COALESCE, correlated subquery.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsCreated,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersCreated,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScoreReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreReceived,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate,
        -- Correlated subquery to find the absolute latest historical activity for a user
        (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.UserId = U.Id) AS LastHistoryActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.CreationDate, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    -- Provides detailed metrics for each post, including edit counts, closure status, and content analysis.
    -- Features: Multiple correlated subqueries, CASE WHEN, GREATEST, string functions for content.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Score AS CurrentPostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.Body AS PostBody, -- Including body for string analysis
        P.Tags AS PostTagsRaw, -- Raw tags for LATERAL JOIN expansion later
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        -- Correlated subquery for counting significant edits (title, body, tags)
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS SignificantEditCount,
        -- Correlated subquery to determine if a post was closed and then subsequently reopened
        (SELECT
            CASE WHEN EXISTS (SELECT 1 FROM PostHistory PH_Closed WHERE PH_Closed.PostId = P.Id AND PH_Closed.PostHistoryTypeId = 10)
                 AND EXISTS (SELECT 1 FROM PostHistory PH_Reopened WHERE PH_Reopened.PostId = P.Id AND PH_Reopened.PostHistoryTypeId = 11 AND PH_Reopened.CreationDate > COALESCE((SELECT MAX(CreationDate) FROM PostHistory PH_MaxClosed WHERE PH_MaxClosed.PostId = P.Id AND PH_MaxClosed.PostHistoryTypeId = 10), '1900-01-01'::timestamp))
            THEN TRUE ELSE FALSE END
        ) AS WasClosedThenReopened,
        -- Calculate the latest significant activity date for the post
        GREATEST(
            P.CreationDate,
            COALESCE(P.LastEditDate, '1900-01-01'::timestamp),
            COALESCE((SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id), '1900-01-01'::timestamp),
            COALESCE((SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = P.Id), '1900-01-01'::timestamp)
        ) AS LastSignificantActivityDate,
        -- String expression: check if body contains a code block and specific keywords
        (P.Body LIKE '%<pre><code>%</pre></code>%' AND (P.Body LIKE '%SQL%' OR P.Body LIKE '%Python%' OR P.Body LIKE '%JavaScript%')) AS ContainsCodeAndKeywords
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community-owned posts or deleted user posts for this analysis
),
MonthlyUserPostFrequency AS (
    -- Uses window functions to analyze user's post frequency and ranking within each month.
    -- Features: DATE_TRUNC, ROW_NUMBER, LAG, EXTRACT, NULLIF for calculation.
    SELECT
        PDM.OwnerUserId AS UserId,
        PDM.PostId,
        PDM.PostCreationDate,
        DATE_TRUNC('month', PDM.PostCreationDate) AS ActivityMonth,
        PDM.CurrentPostScore,
        ROW_NUMBER() OVER (PARTITION BY PDM.OwnerUserId, DATE_TRUNC('month', PDM.PostCreationDate) ORDER BY PDM.CurrentPostScore DESC, PDM.PostCreationDate DESC) AS MonthlyScoreRank,
        LAG(PDM.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.PostCreationDate) AS PreviousPostDate,
        NULLIF(EXTRACT(EPOCH FROM (PDM.PostCreationDate - LAG(PDM.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.PostCreationDate))) / 86400.0, 0.0) AS DaysSincePreviousPost
    FROM PostDetailedMetrics PDM
),
TagAggregateMetrics AS (
    -- Aggregates performance metrics for each tag across all relevant posts.
    -- Features: string_to_array, SUBSTRING, LENGTH, TRIM, AVG.
    SELECT
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(P.Id) AS TotalPostsWithTag,
        AVG(P.Score) AS AvgScoreWithTag,
        AVG(P.ViewCount) AS AvgViewsWithTag,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueUsersForTag
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1 -- Tags are primarily on questions
    GROUP BY TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))
    HAVING COUNT(P.Id) > 50 -- Only consider sufficiently used tags
)
-- Main query combining all CTEs, focusing on two distinct user segments via UNION ALL
-- Features: UNION ALL, LATERAL JOIN, multiple window functions, complex CASE WHEN, NULL handling, string expressions, elaborate predicates.
SELECT
    'High-Reputation Active Contributor' AS UserSegmentType,
    U.UserId,
    U.DisplayName,
    U.Reputation,
    U.TotalPostsCreated,
    U.TotalQuestionsCreated,
    U.TotalAnswersCreated,
    U.AvgPostScoreReceived,
    U.TotalCommentsMade,
    U.TotalBadgesEarned,
    MAX(MPF.MonthlyScoreRank) FILTER (WHERE MPF.MonthlyScoreRank = 1) AS MonthlyTopPostCount,
    AVG(MPF.DaysSincePreviousPost) FILTER (WHERE MPF.DaysSincePreviousPost IS NOT NULL) AS AvgDaysBetweenPosts,
    SUM(PDM.WasClosedThenReopened::int) AS PostsReopenedCount,
    SUM(PDM.ContainsCodeAndKeywords::int) AS PostsWithCodeAndKeywordsCount,
    SUM(CASE
            WHEN PDM.PostTypeId = 1 AND PDM.HasAcceptedAnswer THEN 1
            WHEN PDM.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = PDM.PostId AND Q.AcceptedAnswerId = PDM.PostId) THEN 1
            ELSE 0
        END) AS PostsAcceptedOrAnsweredAcceptedCount,
    -- Window function: user's reputation percentile compared to all users
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
    -- Window function: cumulative distribution of posts by score for this user
    CUME_DIST() OVER (PARTITION BY U.UserId ORDER BY PDM.CurrentPostScore DESC) AS PostScoreCumeDist,
    -- User's primary tag based on average score, if any
    (SELECT PT.TagName FROM (
        SELECT
            TRIM(unnest(string_to_array(SUBSTRING(PDM_Inner.PostTagsRaw FROM 2 FOR LENGTH(PDM_Inner.PostTagsRaw) - 2), '><'))) AS TagName,
            AVG(PDM_Inner.CurrentPostScore) AS TagAvgScore
        FROM PostDetailedMetrics PDM_Inner
        WHERE PDM_Inner.OwnerUserId = U.UserId AND PDM_Inner.PostTagsRaw IS NOT NULL AND PDM_Inner.PostTypeId = 1
        GROUP BY TagName
        ORDER BY TagAvgScore DESC, COUNT(PDM_Inner.PostId) DESC
        LIMIT 1
    ) AS PT) AS PrimaryContributionTag,
    -- Example of complex expression combining various metrics into a composite score
    (U.Reputation * 0.5 + U.TotalPostScoreReceived * 0.2 + U.TotalBadgesEarned * 5 + U.TotalAnswersCreated * 0.1) AS CompositeEngagementScore,
    'Reputation: ' || U.Reputation || ', Posts: ' || U.TotalPostsCreated || ', Comments: ' || U.TotalCommentsMade AS UserSummaryString
FROM UserEngagementSummary U
JOIN PostDetailedMetrics PDM ON U.UserId = PDM.OwnerUserId
LEFT JOIN MonthlyUserPostFrequency MPF ON U.UserId = MPF.UserId AND PDM.PostId = MPF.PostId
WHERE
    U.Reputation > 50000 -- High reputation users
    AND U.TotalPostsCreated >= 50
    AND U.LastPostDate > NOW() - INTERVAL '6 months' -- Recent activity
    AND PDM.ViewCount > 1000 -- Only considering impactful posts
GROUP BY
    U.UserId, U.DisplayName, U.Reputation, U.TotalPostsCreated, U.TotalQuestionsCreated,
    U.TotalAnswersCreated, U.AvgPostScoreReceived, U.TotalCommentsMade, U.TotalBadgesEarned
HAVING
    COUNT(DISTINCT PDM.PostId) > 5 -- At least 5 analyzed posts for the user
    AND SUM(PDM.SignificantEditCount) > U.TotalPostsCreated * 0.5 -- Significant editing activity
UNION ALL
SELECT
    'New-to-Mid Reputation & Active User' AS UserSegmentType,
    U.UserId,
    U.DisplayName,
    U.Reputation,
    U.TotalPostsCreated,
    U.TotalQuestionsCreated,
    U.TotalAnswersCreated,
    U.AvgPostScoreReceived,
    U.TotalCommentsMade,
    U.TotalBadgesEarned,
    MAX(MPF.MonthlyScoreRank) FILTER (WHERE MPF.MonthlyScoreRank = 1) AS MonthlyTopPostCount,
    AVG(MPF.DaysSincePreviousPost) FILTER (WHERE MPF.DaysSincePreviousPost IS NOT NULL) AS AvgDaysBetweenPosts,
    SUM(PDM.WasClosedThenReopened::int) AS PostsReopenedCount,
    SUM(PDM.ContainsCodeAndKeywords::int) AS PostsWithCodeAndKeywordsCount,
    SUM(CASE
            WHEN PDM.PostTypeId = 1 AND PDM.HasAcceptedAnswer THEN 1
            WHEN PDM.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = PDM.PostId AND Q.AcceptedAnswerId = PDM.PostId) THEN 1
            ELSE 0
        END) AS PostsAcceptedOrAnsweredAcceptedCount,
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
    CUME_DIST() OVER (PARTITION BY U.UserId ORDER BY PDM.CurrentPostScore DESC) AS PostScoreCumeDist,
    (SELECT PT.TagName FROM (
        SELECT
            TRIM(unnest(string_to_array(SUBSTRING(PDM_Inner.PostTagsRaw FROM 2 FOR LENGTH(PDM_Inner.PostTagsRaw) - 2), '><'))) AS TagName,
            AVG(PDM_Inner.CurrentPostScore) AS TagAvgScore
        FROM PostDetailedMetrics PDM_Inner
        WHERE PDM_Inner.OwnerUserId = U.UserId AND PDM_Inner.PostTagsRaw IS NOT NULL AND PDM_Inner.PostTypeId = 1
        GROUP BY TagName
        ORDER BY TagAvgScore DESC, COUNT(PDM_Inner.PostId) DESC
        LIMIT 1
    ) AS PT) AS PrimaryContributionTag,
    (U.Reputation * 0.7 + U.TotalPostScoreReceived * 0.1 + U.TotalBadgesEarned * 3 + U.TotalQuestionsCreated * 0.1) AS CompositeEngagementScore,
    'Reputation: ' || U.Reputation || ', Posts: ' || U.TotalPostsCreated || ', Comments: ' || U.TotalCommentsMade AS UserSummaryString
FROM UserEngagementSummary U
JOIN PostDetailedMetrics PDM ON U.UserId = PDM.OwnerUserId
LEFT JOIN MonthlyUserPostFrequency MPF ON U.UserId = MPF.UserId AND PDM.PostId = MPF.PostId
WHERE
    U.Reputation BETWEEN 1000 AND 50000 -- Mid-range reputation users
    AND U.TotalPostsCreated BETWEEN 10 AND 100
    AND U.CreationDate > NOW() - INTERVAL '2 years' -- Relatively newer users
    AND PDM.CurrentPostScore > 5 -- Posts with at least some positive engagement
GROUP BY
    U.UserId, U.DisplayName, U.Reputation, U.TotalPostsCreated, U.TotalQuestionsCreated,
    U.TotalAnswersCreated, U.AvgPostScoreReceived, U.TotalCommentsMade, U.TotalBadgesEarned
HAVING
    COUNT(DISTINCT PDM.PostId) > 3 -- At least 3 analyzed posts
    AND AVG(NULLIF(PDM.FavoriteCount, 0)) > 10 -- Posts are frequently favorited (on average)
ORDER BY
    CompositeEngagementScore DESC, Reputation DESC
LIMIT 500;