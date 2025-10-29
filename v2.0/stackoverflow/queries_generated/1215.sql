-- {"query": "1215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3619} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT PH_Edit.PostId) AS TotalPostEdits,
        COUNT(DISTINCT PH_Close.PostId) AS TotalPostCloses,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MIN(P.CreationDate) AS FirstPostActivity,
        -- String expression and NULL logic for AboutMe snippet
        COALESCE(SUBSTRING(U.AboutMe, 1, 100), 'No description provided') AS AboutMeSnippet,
        -- Conditional aggregation for gold/silver/bronze badges
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH_Edit ON U.Id = PH_Edit.UserId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Edits, rollbacks, suggested edits applied
    LEFT JOIN PostHistory PH_Close ON U.Id = PH_Close.UserId AND PH_Close.PostHistoryTypeId = 10 -- Post closed
    WHERE U.Reputation >= 100
      AND U.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Only relatively active users
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe
),
PostTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        -- Extract first tag, handling NULLs and string format
        SUBSTRING(P.Tags, 2, POSITION('>' IN P.Tags) - 2) AS PrimaryTag,
        -- Check for specific tags (complicated predicate)
        CASE
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' THEN TRUE
            ELSE FALSE
        END AS IsDatabaseRelated,
        -- Correlated Subquery: Check if post has an accepted answer by the owner of the question (if it's a question)
        P.AcceptedAnswerId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM Posts AS AcceptedA
            WHERE AcceptedA.Id = P.AcceptedAnswerId AND AcceptedA.OwnerUserId = P.OwnerUserId
        ) AS AcceptedBySelf,
        -- Uncorrelated Subqueries: Max and Avg comment score for each post
        (SELECT MAX(C.Score) FROM Comments C WHERE C.PostId = P.Id) AS MaxCommentScore,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = P.Id) AS AvgCommentScore,
        -- Window function: Rank posts by creation date for each user
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS rn_latest_post_by_user
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate >= (NOW() - INTERVAL '3 years') -- Only recent posts
),
PostHistoryDetails AS ( -- Granular history details including LAG for time difference
    SELECT
        PH.Id,
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate,
        -- Window function: Calculate time difference between consecutive history entries for a post
        LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
      AND PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 19, 20) -- Relevant history types for activity
),
UserPostHistoryAgg AS ( -- Aggregated history, now calculating max interval
    SELECT
        PHD.UserId,
        PHD.PostId,
        MIN(PHD.CreationDate) AS FirstHistoryDate,
        MAX(PHD.CreationDate) AS LastHistoryDate,
        COUNT(PHD.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PHD.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS MajorEdits, -- Actual content/title/tag edits
        SUM(CASE WHEN PHD.PostHistoryTypeId IN (10) THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN PHD.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS ReopenEvents,
        -- Max time gap between history events in seconds
        MAX(EXTRACT(EPOCH FROM (PHD.CreationDate - PHD.PreviousHistoryDate))) AS MaxIntervalBetweenEditsSeconds
    FROM PostHistoryDetails PHD
    GROUP BY PHD.UserId, PHD.PostId
),
PostVoteAnalysis AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN V.VoteTypeId = 9 THEN V.BountyAmount ELSE 0 END) AS TotalBountyReceived
    FROM Votes V
    WHERE V.VoteTypeId IN (2, 3, 8, 9) -- Up, Down, Bounty Start, Bounty Close
    GROUP BY V.PostId
),
ActiveCommenters AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS UserCommentCount,
        MAX(C.CreationDate) AS LastCommentDate,
        MIN(C.CreationDate) AS FirstCommentDate,
        -- String expression: check for specific keywords in comments
        COUNT(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' THEN 1 ELSE NULL END) AS BugReportComments
    FROM Comments C
    WHERE C.UserId IS NOT NULL
      AND C.CreationDate >= (NOW() - INTERVAL '2 years')
    GROUP BY C.UserId
    HAVING COUNT(C.Id) >= 5 -- Only users with at least 5 comments
)
-- Main query combining all CTEs
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalComments,
    UAS.TotalBadges,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.AboutMeSnippet,
    -- Complicated calculation: average score per post type for questions vs answers
    COALESCE(UAS.TotalPostScore / NULLIF(UAS.TotalPosts, 0), 0) AS AvgScorePerPost,
    COALESCE(UAS.TotalQuestions / NULLIF(UAS.TotalPosts, 0), 0.0) AS QuestionPostRatio,
    -- Time difference calculations (NULL logic)
    EXTRACT(DAY FROM (UAS.LastPostActivity - UAS.FirstPostActivity)) AS DaysActiveInPosts,
    EXTRACT(HOUR FROM (NOW() - UAS.LastAccessDate)) AS HoursSinceLastAccess,
    AC.UserCommentCount,
    AC.BugReportComments,
    -- Correlated Subquery in SELECT for average history entries per post for a user
    (SELECT AVG(UPA.TotalHistoryEntries) FROM UserPostHistoryAgg UPA WHERE UPA.UserId = UAS.UserId) AS AvgHistoryEntriesPerPost,
    SUM(CASE WHEN PTA.IsDatabaseRelated THEN 1 ELSE 0 END) AS DatabaseRelatedPosts,
    SUM(CASE WHEN PTA.AcceptedBySelf THEN 1 ELSE 0 END) AS SelfAcceptedAnswers,
    SUM(PTA.MaxCommentScore) AS TotalMaxCommentScores,
    SUM(PV.UpVoteCount) AS TotalUserUpVotesReceived,
    SUM(PV.DownVoteCount) AS TotalUserDownVotesReceived,
    -- Max time gap between any two consecutive edits for posts owned by the user
    COALESCE(MAX(UPA.MaxIntervalBetweenEditsSeconds), 0) AS MaxTimeGapBetweenPostEdits,
    -- Complex NULL logic for controversial score
    CASE
        WHEN SUM(PV.UpVoteCount) IS NULL AND SUM(PV.DownVoteCount) IS NULL THEN -1 -- No votes recorded
        WHEN COALESCE(SUM(PV.UpVoteCount), 0) = 0 AND SUM(PV.DownVoteCount) > 0 THEN -100 -- Only downvotes
        WHEN SUM(PV.DownVoteCount) > COALESCE(SUM(PV.UpVoteCount), 0) THEN COALESCE(SUM(PV.UpVoteCount), 0) - SUM(PV.DownVoteCount) -- More downvotes than upvotes
        ELSE COALESCE(SUM(PV.UpVoteCount), 0) - SUM(PV.DownVoteCount)
    END AS ControversialScoreMetric
FROM UserActivitySummary UAS
LEFT JOIN PostTagAnalysis PTA ON UAS.UserId = PTA.OwnerUserId AND PTA.rn_latest_post_by_user <= 5 -- Consider only the latest 5 posts for tag analysis per user
LEFT JOIN PostVoteAnalysis PV ON PTA.PostId = PV.PostId
LEFT JOIN ActiveCommenters AC ON UAS.UserId = AC.UserId
LEFT JOIN UserPostHistoryAgg UPA ON UAS.UserId = UPA.UserId AND PTA.PostId = UPA.PostId -- Join UPA for MaxIntervalBetweenEditsSeconds
WHERE UAS.TotalPosts > 0 -- Ensure users have at least one post
  AND UAS.Reputation > 500
  -- Complex predicate with OR and AND (NULL logic for ClosedDate)
  AND (PTA.IsDatabaseRelated = TRUE OR (UAS.TotalAnswers > UAS.TotalQuestions AND PTA.ClosedDate IS NULL))
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalComments,
    UAS.TotalBadges,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.AboutMeSnippet,
    UAS.LastPostActivity,
    UAS.FirstPostActivity,
    UAS.LastAccessDate,
    AC.UserCommentCount,
    AC.BugReportComments
HAVING
    SUM(CASE WHEN PTA.PostTypeId = 1 THEN PTA.PostScore ELSE 0 END) > 50 -- Questions with significant scores
    AND SUM(PV.UpVoteCount) > 10 -- User received some upvotes
    -- Correlated subquery in HAVING clause: check if the user has any posts that were reopened
    AND EXISTS (
        SELECT 1
        FROM UserPostHistoryAgg UPH_inner
        WHERE UPH_inner.UserId = UAS.UserId AND UPH_inner.ReopenEvents > 0
    )
ORDER BY
    UAS.Reputation DESC, ControversialScoreMetric ASC
LIMIT 100

UNION ALL -- Set operator: Combine with highly viewed but not necessarily highly scored questions by other users

SELECT
    P.OwnerUserId AS UserId,
    U.DisplayName,
    U.Reputation,
    1 AS TotalPosts, -- Dummy value for this part of the UNION
    1 AS TotalQuestions,
    0 AS TotalAnswers,
    P.Score AS TotalPostScore,
    0 AS TotalComments,
    0 AS TotalBadges,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    COALESCE(SUBSTRING(U.AboutMe, 1, 100), 'N/A') AS AboutMeSnippet,
    P.Score AS AvgScorePerPost,
    1.0 AS QuestionPostRatio,
    EXTRACT(DAY FROM (P.LastActivityDate - P.CreationDate)) AS DaysActiveInPosts,
    EXTRACT(HOUR FROM (NOW() - U.LastAccessDate)) AS HoursSinceLastAccess,
    0 AS UserCommentCount,
    0 AS BugReportComments,
    (SELECT AVG(PH.TotalHistoryEntries) FROM UserPostHistoryAgg PH WHERE PH.UserId = P.OwnerUserId) AS AvgHistoryEntriesPerPost,
    (CASE WHEN P.Tags LIKE '%<java>%' OR P.Tags LIKE '%<javascript>%' THEN 1 ELSE 0 END) AS DatabaseRelatedPosts, -- Check for popular dev tags
    0 AS SelfAcceptedAnswers,
    0 AS TotalMaxCommentScores,
    (SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id) AS TotalUserUpVotesReceived,
    (SELECT SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id) AS TotalUserDownVotesReceived,
    -- Get max interval for the specific post using a subquery
    COALESCE((SELECT MAX(EXTRACT(EPOCH FROM (PHD_inner.CreationDate - PHD_inner.PreviousHistoryDate))) FROM PostHistoryDetails PHD_inner WHERE PHD_inner.PostId = P.Id), 0) AS MaxTimeGapBetweenPostEdits,
    0 AS ControversialScoreMetric
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
WHERE P.PostTypeId = 1 -- Only questions
  AND P.ViewCount > 50000 -- Highly viewed
  AND P.Score < 100 -- But not necessarily high score
  AND P.CreationDate >= (NOW() - INTERVAL '2 years')
  AND P.OwnerUserId IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 -- Not a duplicate post
  )
  -- Null logic: Only include if ClosedDate is either null or very recent (reopened)
  AND (P.ClosedDate IS NULL OR P.ClosedDate >= (NOW() - INTERVAL '3 months'))
ORDER BY
    Reputation DESC, TotalPostScore DESC
LIMIT 50;
