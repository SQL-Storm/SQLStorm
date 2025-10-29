-- {"query": "1207.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2333} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates initial user activity (posts, comments, votes, badges)
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCreated,
        COUNT(c.Id) AS TotalCommentsMade,
        COUNT(v.Id) AS TotalVotesCast,
        COUNT(b.Id) AS TotalBadgesEarned,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 AND SUM(p.Score) IS NOT NULL -- Filter for users with a minimum activity
),
PostEditActivity AS (
    -- CTE 2: Summarizes post history events, focusing on edits, rollbacks, and close votes
    SELECT
        ph.UserId,
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) AS RollbackCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN ph.Id END) AS CloseVoteCount,
        MAX(LENGTH(ph.Text)) AS MaxHistoryTextLength,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN LENGTH(ph.Text) ELSE 0 END) AS TotalEditTextLength
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL -- Exclude community/anonymous edits for user-specific analysis
    GROUP BY ph.UserId, ph.PostId
    HAVING COUNT(ph.Id) > 1 -- Posts with multiple history events
),
UserOverallActivity AS (
    -- CTE 3: Combines user engagement with post editing activity
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.TotalPostScore,
        ue.TotalPostsCreated,
        ue.QuestionsCreated,
        ue.AnswersCreated,
        ue.TotalCommentsMade,
        ue.TotalVotesCast,
        ue.TotalBadgesEarned,
        ue.LatestPostDate,
        ue.EarliestPostDate,
        COALESCE(SUM(pea.TotalHistoryEvents), 0) AS UserTotalHistoryEvents,
        COALESCE(SUM(pea.EditCount), 0) AS UserTotalEdits,
        COALESCE(SUM(pea.RollbackCount), 0) AS UserTotalRollbacks,
        COALESCE(SUM(pea.CloseVoteCount), 0) AS UserTotalCloseVotes,
        COALESCE(MAX(pea.MaxHistoryTextLength), 0) AS UserMaxHistoryTextLength,
        COALESCE(SUM(pea.TotalEditTextLength), 0) AS UserTotalEditContentLength,
        DATE_PART('year', ue.UserCreationDate) AS UserCreationYear -- Extract year for cohort analysis
    FROM UserEngagement AS ue
    LEFT JOIN PostEditActivity AS pea ON ue.UserId = pea.UserId
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.UserCreationDate, ue.TotalPostScore,
        ue.TotalPostsCreated, ue.QuestionsCreated, ue.AnswersCreated, ue.TotalCommentsMade,
        ue.TotalVotesCast, ue.TotalBadgesEarned, ue.LatestPostDate, ue.EarliestPostDate
),
ModeratorReviewVotes AS (
    -- CTE 4: Identifies users who have cast moderator review votes
    SELECT DISTINCT UserId
    FROM Votes
    WHERE VoteTypeId = 15 -- ModeratorReview vote type
),
HighScoringContributors AS (
    -- CTE 5: Users with significantly high total post scores
    SELECT
        uoa.UserId,
        uoa.DisplayName,
        uoa.Reputation,
        uoa.UserCreationDate,
        uoa.TotalPostScore,
        uoa.TotalPostsCreated,
        uoa.UserTotalEdits,
        uoa.UserTotalCloseVotes,
        uoa.UserCreationYear,
        'High Scoring Contributor' AS ContributorType
    FROM UserOverallActivity AS uoa
    WHERE uoa.TotalPostScore > (SELECT AVG(TotalPostScore) * 2 FROM UserOverallActivity WHERE TotalPostScore IS NOT NULL)
      AND uoa.TotalPostsCreated >= 10
),
HighVolumeEditors AS (
    -- CTE 6: Users with significantly high volume of post edits
    SELECT
        uoa.UserId,
        uoa.DisplayName,
        uoa.Reputation,
        uoa.UserCreationDate,
        uoa.TotalPostScore,
        uoa.TotalPostsCreated,
        uoa.UserTotalEdits,
        uoa.UserTotalCloseVotes,
        uoa.UserCreationYear,
        'High Volume Editor' AS ContributorType
    FROM UserOverallActivity AS uoa
    WHERE uoa.UserTotalEdits > (SELECT AVG(UserTotalEdits) * 3 FROM UserOverallActivity WHERE UserTotalEdits IS NOT NULL)
      AND uoa.TotalPostsCreated >= 5
)
SELECT
    combined.UserId,
    combined.DisplayName,
    combined.Reputation,
    combined.UserCreationDate,
    combined.ContributorType,
    combined.TotalPostScore,
    combined.TotalPostsCreated,
    combined.UserTotalEdits,
    combined.UserTotalCloseVotes,
    -- Complicated predicate/expression/calculation: Ratio of edits per post
    CAST(combined.UserTotalEdits AS DECIMAL) / NULLIF(combined.TotalPostsCreated, 0) AS EditsPerPostRatio,
    -- Window functions for peer comparison and ranking
    AVG(combined.TotalPostScore) OVER (PARTITION BY combined.UserCreationYear, combined.ContributorType) AS AvgScoreInCohortType,
    RANK() OVER (PARTITION BY combined.ContributorType ORDER BY combined.Reputation DESC, combined.TotalPostsCreated DESC) AS RankWithinContributorType,
    NTILE(5) OVER (ORDER BY combined.UserTotalEdits DESC, combined.TotalPostScore DESC) AS OverallPowerUserQuintile,
    -- Correlated subquery 1: Finds the most frequently used and highest-scoring tag for a user's questions
    (
        SELECT t.TagName
        FROM Posts AS p
        -- Assuming PostgreSQL's string_to_array and UNNEST for tag parsing as hinted in schema
        JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name ON TRUE
        JOIN Tags AS t ON t.TagName = tag_name
        WHERE p.OwnerUserId = combined.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY t.TagName
        ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC
        LIMIT 1
    ) AS TopQuestionTag,
    -- Correlated subquery 2: Checks if the user has any 'Off-topic' closed posts
    EXISTS (
        SELECT 1
        FROM PostHistory AS ph
        WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = combined.UserId)
          AND ph.PostHistoryTypeId = 10 -- Post Closed
          AND ph.Comment = '102' -- CloseReasonTypes ID for 'Off-topic'
    ) AS HasOffTopicClosedPosts,
    -- String expressions: Truncate display name and check for a pattern
    LEFT(TRIM(combined.DisplayName), 10) AS DisplayNameTruncated,
    CASE WHEN combined.DisplayName LIKE '% Stack%' THEN 'Stacker' ELSE 'Non-Stacker' END AS DisplayNamePattern,
    -- NULL logic and more expressions: Determine moderator review status
    COALESCE(
        (SELECT 'Has Moderator Reviews' FROM ModeratorReviewVotes mrv WHERE mrv.UserId = combined.UserId),
        'No Moderator Reviews'
    ) AS ModeratorReviewStatus,
    -- Complex CASE expression for user role classification
    CASE
        WHEN combined.Reputation >= 10000 AND combined.UserTotalEdits >= 100 AND combined.ContributorType = 'High Scoring Contributor'
            THEN 'Elite Visionary'
        WHEN combined.Reputation >= 5000 AND combined.UserTotalEdits >= 50 AND combined.ContributorType = 'High Volume Editor'
            THEN 'Master Craftsman'
        ELSE 'Dedicated Member'
    END AS UserRoleClassification
FROM (
    -- Set operator: UNION ALL combines high-scoring contributors and high-volume editors
    SELECT * FROM HighScoringContributors
    UNION ALL
    SELECT * FROM HighVolumeEditors
) AS combined
WHERE
    combined.Reputation >= 1000 -- Base reputation filter for final selection
    AND (combined.UserTotalEdits + combined.UserTotalCloseVotes) > 5 -- Ensure some level of modification/moderation activity
ORDER BY
    combined.Reputation DESC,
    combined.TotalPostScore DESC,
    combined.UserTotalEdits DESC
LIMIT 200;
