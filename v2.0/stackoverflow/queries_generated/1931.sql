-- {"query": "1931.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3360} 

WITH UserActivitySummary AS (
    -- Gathers comprehensive activity metrics for each user, including post counts, vote metrics, badge counts,
    -- and ranks users based on their reputation and total post score.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.WebsiteUrl,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        RANK() OVER (ORDER BY U.Reputation DESC, COALESCE(SUM(P.Score), 0) DESC) AS OverallReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- UpMod, DownMod
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.AboutMe, U.WebsiteUrl
),
PostHistoryAnalysis AS (
    -- Analyzes post history for each post, counting edits, moderation actions (closed/reopened/migrated),
    -- and detecting specific event sequences like close-reopen cycles.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TimesClosed,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TimesReopened,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (17, 35, 36) THEN 1 ELSE 0 END) AS TimesMigrated,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        MIN(PH.CreationDate) AS FirstHistoryEventDate,
        -- Detects if a post was closed and then reopened within a 30-day window
        MAX(CASE
            WHEN PH.PostHistoryTypeId = 11 AND EXISTS (
                SELECT 1 FROM PostHistory PH2
                WHERE PH2.PostId = PH.PostId AND PH2.PostHistoryTypeId = 10
                  AND PH2.CreationDate < PH.CreationDate
                  AND PH2.CreationDate >= PH.CreationDate - INTERVAL '30 day'
            ) THEN 1 ELSE 0
        END) AS HasRecentClosedReopenedCycle,
        -- Retrieves the comment/reason for the most recent 'Post Closed' event
        SUBSTRING(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate || '|||' || PH.Comment END) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC), POSITION('|||' IN MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate || '|||' || PH.Comment END) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC)) + 3) AS LastCloseReasonComment,
        -- Calculates the average time in hours between any two consecutive edit events for a given post.
        -- This is a highly correlated subquery for benchmarking complexity.
        (SELECT AVG(EXTRACT(EPOCH FROM (current_ph.CreationDate - prev_ph.CreationDate))) / 3600.0
         FROM PostHistory current_ph
         JOIN PostHistory prev_ph ON current_ph.PostId = prev_ph.PostId
         WHERE current_ph.PostId = PH.PostId
           AND current_ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Is an edit event
           AND prev_ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Is an edit event
           AND current_ph.CreationDate > prev_ph.CreationDate
           AND NOT EXISTS ( -- Ensures 'prev_ph' is the immediate preceding edit
               SELECT 1 FROM PostHistory middle_ph
               WHERE middle_ph.PostId = current_ph.PostId
                 AND middle_ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)
                 AND middle_ph.CreationDate > prev_ph.CreationDate
                 AND middle_ph.CreationDate < current_ph.CreationDate
           )
        ) AS AvgHoursBetweenEdits
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostTagDecomposition AS (
    -- Deconstructs the 'Tags' string column into individual tag names for each question.
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags != '><' AND P.PostTypeId = 1 -- Only questions for meaningful tags
),
UserTopTagAffinity AS (
    -- Identifies the top tag a user contributes to based on post count.
    SELECT
        P.OwnerUserId AS UserId,
        PTD.TagName,
        COUNT(PTD.PostId) AS UserPostsInTag,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(PTD.PostId) DESC, MAX(P.CreationDate) DESC) AS Rn
    FROM Posts P
    JOIN PostTagDecomposition PTD ON P.Id = PTD.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, PTD.TagName
)
-- Main Query: Combines insights from various CTEs to identify high-engagement posts and influential users.
-- This query uses UNION ALL to present two different perspectives with a consistent output schema.
-- Part 1: Identifies "High-Engagement Posts"
SELECT
    'HighEngagementPost' AS InsightCategory,
    P.Id AS EntityId,
    P.Title AS EntityName,
    P.Score AS MainScore,
    P.ViewCount AS ActivityCount,
    -- Complex calculation for engagement score for posts
    (P.Score * 0.7 + P.ViewCount / 1000.0 + COALESCE(P.AnswerCount, 0) * 10 + COALESCE(PHA.TotalEdits, 0) * 5 + COALESCE(P.FavoriteCount, 0) * 20) AS EngagementScore,
    P.CreationDate AS CreationDate,
    P.LastActivityDate AS LastActiveDate,
    P.OwnerUserId AS RelatedEntityId,
    UAS.DisplayName AS RelatedEntityName,
    P.Tags AS TagsOrLocationInfo,
    COALESCE(PHA.TotalEdits, 0) AS ComplexMetric_A, -- Total Edits
    COALESCE(PHA.TimesClosed, 0) AS ComplexMetric_B, -- Times Closed
    -- Correlated Subquery: Calculates the average score of answers to this specific question
    (SELECT AVG(P_ANS.Score)
     FROM Posts P_ANS
     WHERE P_ANS.ParentId = P.Id AND P_ANS.PostTypeId = 2
    ) AS CorrelatedMetric,
    DENSE_RANK() OVER (
        ORDER BY P.Score DESC, P.ViewCount DESC, COALESCE(P.AnswerCount, 0) DESC, COALESCE(PHA.TotalEdits, 0) DESC
    ) AS RankInSegment,
    (CASE
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
        ELSE 'Open'
    END) || COALESCE(' | Last Close: ' || PHA.LastCloseReasonComment, '') AS DescriptiveNote,
    (PHA.HasRecentClosedReopenedCycle = 1 OR P.CommentCount > 20 OR P.FavoriteCount > 5 OR (PHA.AvgHoursBetweenEdits IS NOT NULL AND PHA.AvgHoursBetweenEdits < 24)) AS HasFlaggedActivity -- Boolean flag for special activity or rapid edits
FROM Posts P
LEFT JOIN UserActivitySummary UAS ON P.OwnerUserId = UAS.UserId
LEFT JOIN PostHistoryAnalysis PHA ON P.Id = PHA.PostId
WHERE P.PostTypeId = 1 -- Only questions
  AND P.CreationDate >= (NOW() - INTERVAL '5 year') -- Recent enough posts
  AND P.Score > 50
  AND P.ViewCount > 50000
  AND (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<performance>%')
  AND COALESCE(UAS.Reputation, 0) > 1000 -- Only questions from users with at least 1000 reputation
  AND NOT EXISTS ( -- Correlated Subquery in WHERE: Exclude questions that are very old duplicates
      SELECT 1 FROM PostLinks PL
      JOIN Posts P_DUP ON PL.RelatedPostId = P_DUP.Id
      WHERE PL.PostId = P.Id
        AND PL.LinkTypeId = 3 -- Duplicate
        AND P_DUP.CreationDate < (NOW() - INTERVAL '7 year')
  )
  AND (P.Body LIKE '%index%' OR P.Body LIKE '%query plan%' OR P.Body LIKE '%transaction%' OR P.Title LIKE '%slow%') -- More specific content filtering
  AND P.AcceptedAnswerId IS NOT NULL -- Only questions with an accepted answer

UNION ALL

-- Part 2: Identifies "Influential Users" with significant contribution and editing footprint
SELECT
    'InfluentialUser' AS InsightCategory,
    UAS.UserId AS EntityId,
    UAS.DisplayName AS EntityName,
    UAS.Reputation AS MainScore,
    UAS.TotalPosts AS ActivityCount,
    -- Complex calculation for engagement score for users
    (UAS.Reputation * 0.5 + UAS.TotalUpvotesReceived / 10.0 + UAS.TotalBadges * 20 + COALESCE(SUM(PHA.TotalEdits), 0) * 2 + (EXTRACT(EPOCH FROM NOW() - UAS.UserCreationDate) / (365.25 * 24 * 3600)) * 100) AS EngagementScore,
    UAS.UserCreationDate AS CreationDate,
    UAS.LastAccessDate AS LastActiveDate,
    NULL AS RelatedEntityId, -- No related entity for user insights
    NULL AS RelatedEntityName,
    UAS.Location AS TagsOrLocationInfo,
    UAS.TotalBadges AS ComplexMetric_A,
    COALESCE(SUM(PHA.TotalEdits), 0) AS ComplexMetric_B, -- Total edits made by this user across all their posts
    -- Correlated Subquery: Average score of non-question posts by this user during their early career
    (SELECT AVG(P_OTHER.Score)
     FROM Posts P_OTHER
     WHERE P_OTHER.OwnerUserId = UAS.UserId
       AND P_OTHER.PostTypeId != 1 -- Not a question (e.g., answer, wiki)
       AND P_OTHER.CreationDate BETWEEN UAS.UserCreationDate AND (UAS.UserCreationDate + INTERVAL '2 year') -- Early career posts
    ) AS CorrelatedMetric,
    NTILE(5) OVER (
        ORDER BY UAS.Reputation DESC, UAS.TotalPosts DESC, UAS.TotalBadges DESC, COALESCE(SUM(PHA.TotalEdits), 0) DESC
    ) AS RankInSegment,
    (CASE
        WHEN LENGTH(COALESCE(UAS.AboutMe, '')) > 500 THEN 'Verbose AboutMe'
        WHEN UAS.WebsiteUrl IS NOT NULL THEN 'Has Website'
        ELSE 'Minimal Profile'
    END) || COALESCE(' | Top Tag: ' || UTTA.TagName, '') AS DescriptiveNote,
    (UAS.TotalUpvotesReceived > 5000 AND UAS.TotalDownvotesReceived > 500) AS HasFlaggedActivity -- User receives many votes both ways (controversial?)
FROM UserActivitySummary UAS
LEFT JOIN Posts P ON UAS.UserId = P.OwnerUserId
LEFT JOIN PostHistoryAnalysis PHA ON P.Id = PHA.PostId
LEFT JOIN UserTopTagAffinity UTTA ON UAS.UserId = UTTA.UserId AND UTTA.Rn = 1 -- Get the user's top tag
WHERE UAS.Reputation > 20000
  AND UAS.TotalPosts > 200
  AND UAS.TotalBadges > 50
  AND UAS.LastAccessDate > (NOW() - INTERVAL '2 year') -- Recently active users
  AND EXISTS ( -- Correlated Subquery in WHERE: User has at least one post with a high edit count
      SELECT 1 FROM PostHistoryAnalysis PHA_INNER
      WHERE P.Id = PHA_INNER.PostId AND PHA_INNER.TotalEdits > 5
  )
  AND (UAS.Location IS NOT NULL AND (UAS.Location ILIKE '%engineer%' OR UAS.Location ILIKE '%developer%' OR UAS.Location ILIKE '%architect%'))
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.LastAccessDate, UAS.TotalPosts,
    UAS.TotalUpvotesReceived, UAS.TotalBadges, UAS.Location, UAS.AboutMe, UAS.WebsiteUrl, UTTA.TagName
ORDER BY EngagementScore DESC, MainScore DESC
LIMIT 1000;
