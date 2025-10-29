-- {"query": "1826.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2537} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 86400 AS UserAgeDays, -- Date calculation
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V_Made.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotesMadeUp, -- UpMod votes made by user
        SUM(CASE WHEN V_Made.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalVotesMadeDown, -- DownMod votes made by user
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END) AS AvgUserPostScore,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        COALESCE(U.Location, 'Unspecified Location') AS UserLocation_Coalesced -- NULL logic
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V_Made ON U.Id = V_Made.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.Location
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(COALESCE(P.Title, 'No Title')) AS TitleLength, -- NULL logic for Title
        ARRAY_LENGTH(string_to_array(TRIM(BOTH '<>' FROM P.Tags), '><'), 1) AS TagCount, -- String function
        (
            SELECT COUNT(DISTINCT PH.Id)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title/Body/Tags
        ) AS PostEditCount, -- Correlated subquery for edit count
        COALESCE(P.AcceptedAnswerId, -999) AS AcceptedAnswerPostId, -- NULL logic, using arbitrary non-existent ID
        CASE
            WHEN P.PostTypeId = 1 AND P.ViewCount > 0 THEN CAST(P.Score AS NUMERIC) / P.ViewCount
            ELSE 0.0
        END AS ScorePerViewRatio, -- Complicated expression
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS UserPostScoreRank, -- Window function
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate -- Window function
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Only Questions and Answers
    AND P.CreationDate >= '2020-01-01' -- Filter for more recent posts
),
TagPerformance AS (
    SELECT
        LOWER(TRIM(unnest(string_to_array(TRIM(BOTH '<>' FROM P.Tags), '><')))) AS TagName, -- String functions
        COUNT(DISTINCT P.Id) AS TaggedPostCount,
        SUM(P.ViewCount) AS TagTotalViews,
        AVG(P.Score) AS AvgTagPostScore
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
    GROUP BY LOWER(TRIM(unnest(string_to_array(TRIM(BOTH '<>' FROM P.Tags), '><'))))
    HAVING COUNT(DISTINCT P.Id) > 50 -- Filter out less common tags
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 END) AS DuplicatePostsCount
    FROM PostLinks PL
    GROUP BY PL.PostId
),
LatestPostHistoryEvent AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS LatestHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC, PH.Id DESC) as rn -- Window function
    FROM PostHistory PH
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserLocation_Coalesced,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.AvgUserPostScore,
    UE.UserAgeDays,
    PQM.PostId,
    PQM.PostCreationDate,
    PQM.PostScore,
    PQM.ViewCount,
    PQM.ScorePerViewRatio,
    PQM.TagCount,
    PQM.PostEditCount,
    (PQM.PostCreationDate - PQM.PreviousPostCreationDate) AS TimeSincePreviousPost, -- Date arithmetic
    TP.TagName AS TopAssociatedTag,
    TP.AvgTagPostScore,
    COALESCE(PLS.LinkedPostsCount, 0) AS LinkedPostsCount, -- NULL logic
    COALESCE(PLS.DuplicatePostsCount, 0) AS DuplicatePostsCount, -- NULL logic
    LPH.LatestHistoryDate,
    PHT.Name AS LatestHistoryTypeName,
    CASE
        WHEN UE.Reputation > 50000 AND PQM.ScorePerViewRatio > 0.5 AND PQM.PostEditCount > 2 THEN 'High-Impact Expert'
        WHEN UE.Reputation > 10000 AND PQM.PostScore > 100 AND PQM.AcceptedAnswerPostId != -999 THEN 'Community Leader'
        WHEN UE.TotalQuestions > 50 AND PQM.TagCount > 3 THEN 'Prolific Contributor'
        WHEN PQM.ClosedDate IS NOT NULL THEN 'Closed Post Contributor' -- NULL logic
        ELSE 'Active User'
    END AS UserPostSegment, -- Complicated CASE expression
    (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = UE.UserId AND B.Class = 1) AS GoldBadgesCount, -- Correlated Subquery
    REPLACE(UPPER(SUBSTRING(UE.DisplayName, 1, 3)), ' ', '_') AS DisplayNamePrefix_Upper -- String manipulation
FROM UserEngagement UE
INNER JOIN PostQualityMetrics PQM ON UE.UserId = PQM.OwnerUserId
LEFT JOIN PostLinkSummary PLS ON PQM.PostId = PLS.PostId -- Outer join
LEFT JOIN LatestPostHistoryEvent LPH ON PQM.PostId = LPH.PostId AND LPH.rn = 1 -- Outer join
LEFT JOIN PostHistoryTypes PHT ON LPH.PostHistoryTypeId = PHT.Id -- Outer join
LEFT JOIN ( -- Subquery to find the top performing tag for each post
    SELECT
        sq.PostId,
        sq.TagName,
        sq.AvgTagPostScore,
        ROW_NUMBER() OVER (PARTITION BY sq.PostId ORDER BY sq.AvgTagPostScore DESC, sq.TaggedPostCount DESC) as rn
    FROM (
        SELECT
            P_sub.Id AS PostId,
            LOWER(TRIM(unnest(string_to_array(TRIM(BOTH '<>' FROM P_sub.Tags), '><')))) AS TagName,
            TP_sub.AvgTagPostScore,
            TP_sub.TaggedPostCount
        FROM Posts P_sub
        CROSS JOIN TagPerformance TP_sub -- CROSS JOIN to evaluate all tag performances
        WHERE P_sub.Tags IS NOT NULL
          AND LOWER(TRIM(unnest(string_to_array(TRIM(BOTH '<>' FROM P_sub.Tags), '><')))) = TP_sub.TagName
          AND P_sub.PostTypeId = 1
    ) sq
) TP ON PQM.PostId = TP.PostId AND TP.rn = 1 -- Outer join
WHERE UE.Reputation > 1000 -- Filter for established users
  AND PQM.PostScore > 5 -- Filter for reasonably good posts
  AND PQM.UserPostScoreRank <= 5 -- Only consider top 5 posts by score for each user (Window function used in filtering)
  AND PQM.BodyLength > 100 -- Ensure substantial content
  AND PQM.AcceptedAnswerPostId IS DISTINCT FROM -999 -- Checks for non-accepted answer posts or questions with accepted answers (NULL-safe comparison)
  AND (UE.UserLocation_Coalesced LIKE '%US%' OR UE.UserLocation_Coalesced IS NULL) -- NULL logic and string pattern
  AND NOT EXISTS (
      SELECT 1
      FROM PostHistory PH_closed
      WHERE PH_closed.PostId = PQM.PostId
        AND PH_closed.PostHistoryTypeId = 10 -- Post Closed
        AND PH_closed.CreationDate > PQM.PostCreationDate + INTERVAL '1 year' -- Closed significantly later
  ) -- Correlated subquery in WHERE
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.UserLocation_Coalesced, UE.TotalQuestions, UE.TotalAnswers,
    UE.AvgUserPostScore, UE.UserAgeDays, PQM.PostId, PQM.PostCreationDate, PQM.PostScore, PQM.ViewCount,
    PQM.ScorePerViewRatio, PQM.TagCount, PQM.PostEditCount, PQM.PreviousPostCreationDate,
    TP.TagName, TP.AvgTagPostScore, PLS.LinkedPostsCount, PLS.DuplicatePostsCount,
    LPH.LatestHistoryDate, PHT.Name, PQM.ClosedDate, PQM.AcceptedAnswerPostId
HAVING
    COUNT(DISTINCT PQM.PostId) > 1 -- Users with more than one qualifying post
    AND MAX(PQM.ScorePerViewRatio) > 0.05 -- At least one post with a decent score/view ratio
ORDER BY
    UE.Reputation DESC,
    PQM.ScorePerViewRatio DESC,
    UE.UserAgeDays DESC
LIMIT 100;
