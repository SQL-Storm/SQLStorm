-- {"query": "1406.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3521} 

WITH UserEngagement AS (
    -- CTE 1: Summarizes user activity and calculates engagement metrics over their lifetime
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous Contributor') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24))::DECIMAL(10, 2) AS EngagementDays, -- Total days since user creation
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(P.Score) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalComments,
        (
            SELECT COUNT(B.Id)
            FROM Badges B
            WHERE B.UserId = U.Id AND B.Class = 1 AND B.Date > U.CreationDate -- Count Gold Badges awarded after creation
        ) AS GoldBadgeCount, -- Correlated subquery for specific badge type count
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) OVER (PARTITION BY U.Id) AS AvgAnswerScore,
        MAX(P.LastActivityDate) AS LastPostActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation >= 150 -- Filter for more established users with some reputation
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0 -- Ensure some form of activity
),
PostHistoricalMetrics AS (
    -- CTE 2: Analyzes post history for edit frequency, closure, reopening, and migration
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.RevisionGUID) AS TotalRevisions,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount, -- Post Closed
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount, -- Post Reopened
        SUM(CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN 1 ELSE 0 END) AS MigrationEventCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(PH.CreationDate) AS FirstHistoryDate,
        -- Calculate average time difference between consecutive edits for a post
        AVG(EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate)))) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS AvgEditTimeDiffSeconds
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId <= 50 -- Focus on primary history types
    GROUP BY PH.PostId
    HAVING COUNT(PH.Id) > 1 -- Only include posts with at least two history entries
),
TagPerformance AS (
    -- CTE 3: Calculates performance metrics for frequently used tags
    SELECT
        TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))) AS TagName,
        COUNT(P.Id) AS TagPostCount,
        AVG(P.Score) AS AvgTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        MAX(P.CreationDate) AS LatestTagPostDate
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))))
    HAVING COUNT(P.Id) >= 100 -- Consider only tags with significant activity
),
UserTopQuestionContribution AS (
    -- CTE 4: Identifies the single top-scoring question for each active user
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.CreationDate AS PostCreationDate,
        P.Title AS PostTitle,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS Rn
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL
      AND P.CreationDate >= (CURRENT_DATE - INTERVAL '2 year') -- Questions from the last two years
      AND P.Score > 0
)
-- Main Query: Integrates user engagement, post history, tag performance, and link data
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.EngagementDays,
    UE.TotalPosts,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalPostScore,
    UE.TotalPostViews,
    UE.GoldBadgeCount,
    UE.AvgAnswerScore,
    TP.TagName AS TopContributingTag,
    TP.AvgTagScore AS TopTagAvgScore,
    TP.AvgTagViewCount AS TopTagAvgViews,
    PHM.TotalRevisions AS TopQuestionRevisions,
    PHM.EditCount AS TopQuestionEditCount,
    PHM.CloseEventCount AS TopQuestionCloseCount,
    PHM.ReopenEventCount AS TopQuestionReopenCount,
    PHM.AvgEditTimeDiffSeconds AS TopQuestionAvgEditGap,
    SQ_Links.LinkedPostCount,
    SQ_Links.DuplicatePostCount,
    -- Window function: Rank users by reputation within their engagement decile, handling potential NULLs
    NTILE(10) OVER (ORDER BY UE.EngagementDays DESC NULLS LAST, UE.Reputation DESC) AS ReputationEngagementDecile,
    -- Complex string expression and NULL logic for user location and display name abbreviation
    COALESCE(U.Location, 'Unknown Region') || ' - ' || UPPER(SUBSTRING(COALESCE(U.DisplayName, 'ANON'), 1, 4)) AS UserGeoAbbrev,
    (
        SELECT
            AVG(V.BountyAmount)
        FROM Votes V
        WHERE V.VoteTypeId = 8 AND V.UserId = UE.UserId AND V.BountyAmount IS NOT NULL AND V.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
    ) AS AvgBountyStartedLastYear, -- Correlated subquery for average bounty started
    CASE
        WHEN UE.TotalPostViews > 150000 AND UE.GoldBadgeCount >= 3 THEN 'Highly Influential Power User'
        WHEN UE.Reputation > 75000 AND UE.EngagementDays > 730 AND UE.QuestionCount >= 20 THEN 'Seasoned Community Leader'
        WHEN UE.QuestionCount > 75 AND UE.AvgAnswerScore > 15 AND UE.TotalPostScore > 1000 THEN 'Prodigious Contributor'
        WHEN UE.TotalComments > 200 AND UE.TotalPosts > 10 THEN 'Engaged Discussion Driver'
        ELSE 'Active Participant'
    END AS UserEngagementCategory,
    -- Calculate days since last activity versus last access
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(UE.LastPostActivityDate, UE.LastAccessDate))) / (60 * 60 * 24))::DECIMAL(10, 2) AS DaysSinceLastActivity
FROM UserEngagement UE
JOIN Users U ON UE.UserId = U.Id
LEFT JOIN (
    -- Subquery for user's most active tag based on post count (questions only)
    SELECT
        OwnerUserId,
        TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><')))) AS TagName,
        COUNT(*) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, MAX(CreationDate) DESC) AS rn_tag
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL AND Tags IS NOT NULL AND LENGTH(Tags) > 2
    GROUP BY OwnerUserId, TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><'))))
) AS UserMostActiveTag ON UE.UserId = UserMostActiveTag.OwnerUserId AND UserMostActiveTag.rn_tag = 1
LEFT JOIN TagPerformance TP ON UserMostActiveTag.TagName = TP.TagName
LEFT JOIN (
    -- Left Join with post history for the user's single top-scoring question
    SELECT
        UTQC.UserId,
        PHM_inner.TotalRevisions,
        PHM_inner.EditCount,
        PHM_inner.CloseEventCount,
        PHM_inner.ReopenEventCount,
        PHM_inner.AvgEditTimeDiffSeconds
    FROM UserTopQuestionContribution UTQC
    JOIN PostHistoricalMetrics PHM_inner ON UTQC.PostId = PHM_inner.PostId
    WHERE UTQC.Rn = 1 -- Only consider the top question
) AS PHM ON UE.UserId = PHM.UserId
LEFT JOIN (
    -- Subquery for linked and duplicate post counts related to any of the user's posts
    SELECT
        P.OwnerUserId,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount
    FROM Posts P
    JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId -- Consider links where user's post is source or target
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
) AS SQ_Links ON UE.UserId = SQ_Links.OwnerUserId
WHERE
    UE.TotalPostScore > 750
    AND UE.EngagementDays > 90
    AND UE.DisplayName NOT LIKE 'user%' -- Filter out generic usernames
    AND (
        UE.GoldBadgeCount > 0
        OR UE.TotalPostViews > 75000
    )
    -- Correlated subquery in WHERE clause for a complex comment activity filter
    AND EXISTS (
        SELECT 1
        FROM Comments C_filter
        WHERE C_filter.UserId = UE.UserId
          AND C_filter.CreationDate > (U.LastAccessDate - INTERVAL '180 days') -- Comments within last 6 months
          AND LENGTH(C_filter.Text) > 75 -- Only meaningful, longer comments
          AND C_filter.Text ILIKE '%explain%' -- Comment content analysis
    )
    AND (U.Location IS NOT NULL OR UE.GoldBadgeCount > 0) -- NULL logic: user must have location OR be highly recognized
-- UNION with another result set: users who are highly active in answering, with significant edits to their answers,
-- even if they don't ask many questions or have specific tags
UNION ALL
SELECT
    UE_ALT.UserId,
    UE_ALT.DisplayName,
    UE_ALT.Reputation,
    UE_ALT.EngagementDays,
    UE_ALT.TotalPosts,
    UE_ALT.QuestionCount,
    UE_ALT.AnswerCount,
    UE_ALT.TotalPostScore,
    UE_ALT.TotalPostViews,
    UE_ALT.GoldBadgeCount,
    UE_ALT.AvgAnswerScore,
    NULL AS TopContributingTag, -- No tag analysis for this branch
    NULL AS TopTagAvgScore,
    NULL AS TopTagAvgViews,
    PHM_ALT.TotalRevisions AS TopAnswerRevisions,
    PHM_ALT.EditCount AS TopAnswerEditCount,
    NULL AS TopAnswerCloseCount, -- Answers generally don't get 'closed'
    NULL AS TopAnswerReopenCount,
    PHM_ALT.AvgEditTimeDiffSeconds AS TopAnswerAvgEditGap,
    NULL AS LinkedPostCount,
    NULL AS DuplicatePostCount,
    NTILE(10) OVER (ORDER BY UE_ALT.AvgAnswerScore DESC NULLS LAST, UE_ALT.Reputation DESC) AS ReputationEngagementDecile,
    COALESCE(U_ALT.Location, 'Remote') || ' - ' || UPPER(SUBSTRING(COALESCE(U_ALT.DisplayName, 'RPLY'), 1, 4)) AS UserGeoAbbrev,
    (
        SELECT
            AVG(V_ALT.BountyAmount)
        FROM Votes V_ALT
        WHERE V_ALT.VoteTypeId = 8 AND V_ALT.UserId = UE_ALT.UserId AND V_ALT.BountyAmount IS NOT NULL AND V_ALT.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
    ) AS AvgBountyStartedLastYear,
    'Dedicated Answerer' AS UserEngagementCategory,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(UE_ALT.LastPostActivityDate, UE_ALT.LastAccessDate))) / (60 * 60 * 24))::DECIMAL(10, 2) AS DaysSinceLastActivity
FROM UserEngagement UE_ALT
JOIN Users U_ALT ON UE_ALT.UserId = U_ALT.Id
LEFT JOIN (
    -- Identify the single top-scoring answer for these users
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS Rn
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.OwnerUserId IS NOT NULL AND P.Score > 0
) AS UserTopAnswerContribution ON UE_ALT.UserId = UserTopAnswerContribution.UserId AND UserTopAnswerContribution.Rn = 1
LEFT JOIN PostHistoricalMetrics PHM_ALT ON UserTopAnswerContribution.PostId = PHM_ALT.PostId
WHERE
    UE_ALT.AnswerCount >= 50 -- At least 50 answers
    AND UE_ALT.AvgAnswerScore >= 10 -- Average answer score of 10 or more
    AND UE_ALT.QuestionCount < 5 -- Primarily focused on answering
    AND UE_ALT.EngagementDays > 365 -- Engaged for at least a year
    AND PHM_ALT.EditCount > 5 -- Top answer has been edited multiple times
ORDER BY Reputation DESC, EngagementDays DESC
LIMIT 1000; -- Limit the overall result set size for benchmarking
