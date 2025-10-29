-- {"query": "1926.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3329} 

WITH UserEngagement AS (
    -- CTE 1: Filters users based on reputation and recent activity.
    -- Calculates counts of different badge classes using correlated subqueries for detailed user profiles.
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges
    FROM Users AS U
    WHERE U.Reputation >= 1000 -- Minimum reputation for active and established users
      AND U.LastAccessDate >= (NOW() - INTERVAL '6 months') -- User must have accessed recently
      AND U.Views >= 50 -- At least some profile visibility
      AND U.AccountId IS NOT NULL -- Ensures a valid associated account
),
PostDetailsWithMetrics AS (
    -- CTE 2: Gathers core post data for questions and answers.
    -- Calculates a 'PostActivityScore' as a weighted sum of various engagement metrics.
    -- Extracts the primary tag using string functions and handles potential NULLs.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.Title AS PostTitle,
        P.Tags,
        COALESCE(
            NULLIF(SUBSTRING(P.Tags FROM '^\<([^\>]+)\>'), ''), -- Extracts first tag, handles empty string after extraction
            'untagged'
        ) AS PrimaryTag,
        ( -- Complex calculation for post activity score
            P.Score * 2
            + COALESCE(P.ViewCount, 0) / 10
            + COALESCE(P.AnswerCount, 0) * 5
            + COALESCE(P.CommentCount, 0) * 3
            + COALESCE(P.FavoriteCount, 0) * 10
            - CASE WHEN P.ClosedDate IS NOT NULL THEN 50 ELSE 0 END -- Penalty for closed posts
        ) AS PostActivityScore
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    WHERE P.OwnerUserId > 0 -- Excludes community user (-1) and deleted users (NULL)
      AND P.PostTypeId IN (1, 2) -- Focuses on Questions (1) and Answers (2)
      AND P.CreationDate >= (NOW() - INTERVAL '2 years') -- Limits to recent posts
      AND P.Body LIKE '%<code>%' -- Filters for posts containing code snippets (often technical)
),
PostHistoryEditSequence AS (
    -- CTE 3: Identifies all edit events for posts and sequences them to calculate time differences.
    -- Uses LAG() window function to find the creation date of the immediately preceding edit.
    SELECT
        PH.Id AS PostHistoryId,
        PH.PostId,
        PH.CreationDate AS EditCreationDate,
        PH.PostHistoryTypeId,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditDate
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Only considers actual edits (Title, Body, Tags)
),
PostEditAndLifecycle AS (
    -- CTE 4: Aggregates post history events to count edits, closes, reopens, and deletes.
    -- Calculates the total time spent between consecutive edits for each post.
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEdits,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 END) AS DeleteEvents,
        -- Sums the time difference (in hours) between consecutive edits, ignoring the first edit
        COALESCE(
            SUM(EXTRACT(EPOCH FROM (PHES.EditCreationDate - PHES.PreviousEditDate))) FILTER (WHERE PHES.PreviousEditDate IS NOT NULL) / 3600.0,
            0
        ) AS TotalTimeBetweenEditsHours,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.UserId END) AS LatestEditorUserId,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.UserDisplayName END), 'Community Editor') AS LatestEditorDisplayName
    FROM PostHistory AS PH
    LEFT JOIN PostHistoryEditSequence AS PHES ON PH.PostId = PHES.PostId AND PH.Id = PHES.PostHistoryId
    GROUP BY PH.PostId
),
CombinedPostData AS (
    -- CTE 5: Merges post details with edit and lifecycle information.
    -- Calculates a 'ControversyScore' based on comments, edits, and close events relative to positive engagement.
    -- Classifies posts into 'PostLifecycleStatus' categories using complex CASE WHEN logic and date arithmetic.
    SELECT
        PD.PostId,
        PD.PostTypeId,
        PD.PostTypeName,
        PD.OwnerUserId,
        PD.PostCreationDate,
        PD.PostScore,
        PD.ViewCount,
        PD.AnswerCount,
        PD.CommentCount,
        PD.FavoriteCount,
        PD.ClosedDate,
        PD.PostTitle,
        PD.Tags,
        PD.PrimaryTag,
        PD.PostActivityScore,
        COALESCE(PEL.TotalEdits, 0) AS TotalEdits,
        COALESCE(PEL.CloseEvents, 0) AS CloseEvents,
        COALESCE(PEL.ReopenEvents, 0) AS ReopenEvents,
        COALESCE(PEL.DeleteEvents, 0) AS DeleteEvents,
        COALESCE(PEL.TotalTimeBetweenEditsHours, 0) AS TotalTimeBetweenEditsHours,
        PEL.LatestEditorUserId,
        PEL.LatestEditorDisplayName,
        ( -- Complex 'Controversy Score' calculation with NULLIF for division by zero safety
            (PD.CommentCount * 2) + (COALESCE(PEL.TotalEdits, 0) * 3) + (COALESCE(PEL.CloseEvents, 0) * 10)
        ) * 1.0 / NULLIF((PD.PostScore + PD.ViewCount / 10.0 + 1), 0) AS ControversyScoreRaw,
        CASE -- Elaborate post lifecycle classification
            WHEN PD.PostCreationDate >= (NOW() - INTERVAL '3 months') AND PD.PostScore >= 10 THEN 'New&Popular'
            WHEN PD.PostCreationDate < (NOW() - INTERVAL '1 year') AND COALESCE(PEL.TotalEdits, 0) >= 5 THEN 'Old&HeavilyEdited'
            WHEN PD.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN PD.PostTypeId = 1 AND COALESCE(PD.AnswerCount, 0) = 0 THEN 'UnansweredQuestion'
            ELSE 'Standard'
        END AS PostLifecycleStatus
    FROM PostDetailsWithMetrics AS PD
    LEFT JOIN PostEditAndLifecycle AS PEL ON PD.PostId = PEL.PostId
),
RankedUserPosts AS (
    -- CTE 6: Ranks posts for each user based on controversy and activity scores.
    -- Uses ROW_NUMBER() for ranking and AVG() OVER (PARTITION BY...) for aggregated post type controversy.
    -- Also counts posts within a year using another window function.
    SELECT
        CPD.*,
        ROW_NUMBER() OVER (PARTITION BY CPD.OwnerUserId ORDER BY CPD.ControversyScoreRaw DESC, CPD.PostActivityScore DESC) AS RankWithinUser,
        AVG(CPD.ControversyScoreRaw) OVER (PARTITION BY CPD.OwnerUserId, CPD.PostTypeName) AS AvgPostTypeControversyScore,
        COUNT(CPD.PostId) OVER (PARTITION BY CPD.OwnerUserId, EXTRACT(YEAR FROM CPD.PostCreationDate)) AS PostsInYear
    FROM CombinedPostData AS CPD
    WHERE CPD.PostScore >= -2 -- Excludes severely downvoted posts
)
-- Final Query: Combines user and post data, applying complex filters and using UNION ALL
-- It creates two distinct segments of users/posts to highlight different aspects of performance.
-- Each segment has specific criteria and focuses on particular post types or user achievements.
SELECT
    'HighReputation_GoldBadge_Questions' AS Segment, -- Identifies the segment for analysis
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    R.PostId,
    R.PostTypeName,
    R.PostTitle,
    R.PostCreationDate,
    R.PostScore,
    R.ViewCount,
    R.PrimaryTag,
    R.TotalEdits,
    R.CloseEvents,
    R.ReopenEvents,
    R.LatestEditorDisplayName,
    R.ControversyScoreRaw AS PostControversyScore,
    R.AvgPostTypeControversyScore,
    R.PostLifecycleStatus,
    R.PostsInYear,
    -- Correlated subquery: Retrieves the most recent comment text made by the post's owner.
    COALESCE(
        (SELECT C.Text FROM Comments AS C WHERE C.PostId = R.PostId AND C.UserId = R.OwnerUserId ORDER BY C.CreationDate DESC LIMIT 1),
        'No owner comment found'
    ) AS LatestOwnerComment,
    -- String expression: Checks if specific technical tags are present.
    (R.Tags LIKE '%<javascript>%' OR R.Tags LIKE '%<python>%') AS IsTechSpecificTag,
    -- NULL logic: Provides a default value for FavoriteCount.
    COALESCE(R.FavoriteCount, 0) AS DisplayFavoriteCount,
    R.TotalTimeBetweenEditsHours
FROM UserEngagement AS UE
INNER JOIN RankedUserPosts AS R ON UE.UserId = R.OwnerUserId
WHERE R.RankWithinUser <= 2 -- Limits to the top 2 most controversial posts per user in this segment
  AND R.PostScore >= 5 -- Minimum post score
  AND UE.GoldBadges > 0 -- Users must have at least one Gold badge
  AND R.PostTypeId = 1 -- Focuses specifically on Questions
  AND R.ControversyScoreRaw > 0.7 -- High controversy threshold for questions
  AND R.PostLifecycleStatus <> 'UnansweredQuestion' -- Excludes questions without answers
  AND UE.Reputation >= 5000 -- Higher reputation requirement for this segment
  AND EXISTS ( -- Complex predicate using EXISTS to check for popular primary tags
        SELECT 1 FROM Tags T WHERE T.TagName = R.PrimaryTag AND T.Count > 1000
    )

UNION ALL

SELECT
    'MidReputation_SilverBadge_Answers' AS Segment, -- Identifies the segment for analysis
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    R.PostId,
    R.PostTypeName,
    R.PostTitle,
    R.PostCreationDate,
    R.PostScore,
    R.ViewCount,
    R.PrimaryTag,
    R.TotalEdits,
    R.CloseEvents,
    R.ReopenEvents,
    R.LatestEditorDisplayName,
    R.ControversyScoreRaw AS PostControversyScore,
    R.AvgPostTypeControversyScore,
    R.PostLifecycleStatus,
    R.PostsInYear,
    -- Correlated subquery: Retrieves the most recent comment text made by the post's owner.
    COALESCE(
        (SELECT C.Text FROM Comments AS C WHERE C.PostId = R.PostId AND C.UserId = R.OwnerUserId ORDER BY C.CreationDate DESC LIMIT 1),
        'No owner comment found'
    ) AS LatestOwnerComment,
    -- String expression: Checks for specific technical tags.
    (R.Tags LIKE '%<database>%' OR R.Tags LIKE '%<sql>%') AS IsTechSpecificTag,
    -- NULL logic: Provides a default value for FavoriteCount.
    COALESCE(R.FavoriteCount, 0) AS DisplayFavoriteCount,
    R.TotalTimeBetweenEditsHours
FROM UserEngagement AS UE
INNER JOIN RankedUserPosts AS R ON UE.UserId = R.OwnerUserId
WHERE R.RankWithinUser <= 3 -- Limits to the top 3 most controversial posts per user in this segment
  AND R.PostScore >= 10 -- Higher minimum score for answers
  AND UE.SilverBadges > 0 -- Users must have at least one Silver badge
  AND R.PostTypeId = 2 -- Focuses specifically on Answers
  AND R.ControversyScoreRaw > 0.3 -- Moderate controversy threshold for answers
  AND R.ViewCount > 500 -- Requires answers to popular questions (implied by question view count)
  AND UE.Reputation BETWEEN 1000 AND 4999 -- Mid-range reputation for this segment
  AND (R.PostTitle ILIKE '%error%' OR R.PostTitle ILIKE '%solution%') -- String expression: Title contains specific keywords (case-insensitive)

ORDER BY
    Segment,
    UE.Reputation DESC,
    R.PostScore DESC,
    R.RankWithinUser;
