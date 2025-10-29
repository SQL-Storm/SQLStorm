-- {"query": "1686.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2411} 
WITH UserDuplicateQuestionClosures AS (
    -- Identify users who own questions that were closed specifically as duplicates
    SELECT DISTINCT p.OwnerUserId AS UserId
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 -- Only consider Questions
      AND p.OwnerUserId IS NOT NULL
      AND ph.PostHistoryTypeId = 10 -- Post Closed event
      AND (
            ph.Comment IN ('1', '101') -- Legacy (Exact Duplicate) or current (Duplicate) CloseReasonType IDs
            OR ph.Text LIKE '%"OriginalQuestionIds":%' -- Check for JSON indicating duplicate in the Text field
          )
),
HighScoreAcceptedAnswers AS (
    -- Identify users who own answers that were accepted by the question owner and received a high score
    SELECT DISTINCT p.OwnerUserId AS UserId
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id -- Join to the parent question
    WHERE p.PostTypeId = 2 -- Only consider Answers
      AND p.OwnerUserId IS NOT NULL
      AND q.AcceptedAnswerId = p.Id -- This specific answer was accepted for its parent question
      AND p.Score >= 50 -- Arbitrary threshold for a "high score"
),
UserTopBadge AS (
    -- Determine the single "best" badge for each user (Gold > Silver > Bronze, then by newest date)
    SELECT
        b.UserId,
        b.Name AS TopBadgeName,
        b.Class AS TopBadgeClass
    FROM (
        SELECT
            b_inner.UserId,
            b_inner.Name,
            b_inner.Class,
            ROW_NUMBER() OVER (PARTITION BY b_inner.UserId ORDER BY b_inner.Class ASC, b_inner.Date DESC) AS rn
        FROM Badges b_inner
    ) AS b
    WHERE b.rn = 1
),
RecentUserActivityStream AS (
    -- Combine recent post and comment activities into a single stream for comprehensive engagement analysis
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS ActivityId,
        'Post' AS ActivityType,
        p.Score,
        p.CreationDate AS ActivityDate,
        p.CommentCount AS PostCommentCount,
        p.PostTypeId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year'
    AND p.PostTypeId IN (1, 2) -- Focus on Questions and Answers

    UNION ALL

    SELECT
        c.UserId AS UserId,
        c.Id AS ActivityId,
        'Comment' AS ActivityType,
        c.Score AS Score, -- Comment score, could be NULL
        c.CreationDate AS ActivityDate,
        NULL AS PostCommentCount, -- Not applicable for comments themselves
        NULL AS PostTypeId -- Not applicable for comments
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year'
),
UserPostEngagementSummary AS (
    -- Aggregate various engagement metrics from the activity stream
    SELECT
        ras.UserId,
        COUNT(DISTINCT CASE WHEN ras.ActivityType = 'Post' THEN ras.ActivityId END) AS TotalRecentPosts,
        AVG(CASE WHEN ras.ActivityType = 'Post' THEN ras.Score END) AS AvgRecentPostScore,
        SUM(CASE WHEN ras.ActivityType = 'Post' THEN ras.PostCommentCount ELSE 0 END) AS TotalRecentPostCommentCount, -- Sum of CommentCount on their posts
        SUM(CASE WHEN ras.ActivityType = 'Comment' THEN 1 ELSE 0 END) AS TotalRecentCommentsMade, -- Number of comments user made
        MAX(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ras.ActivityDate)) / 86400) AS MaxDaysSinceLastActivity, -- Max days since any recent activity
        CAST(SUM(CASE WHEN ras.ActivityType = 'Post' AND ras.PostTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN ras.ActivityType = 'Post' AND ras.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS AnswerQuestionRatio
    FROM RecentUserActivityStream ras
    GROUP BY ras.UserId
),
CrossUserVotingActivity AS (
    -- Identify users who actively vote on posts owned by other users
    SELECT
        v.UserId,
        COUNT(v.Id) AS VotesOnOthersPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnOthersPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnOthersPosts
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.UserId IS NOT NULL
      AND p.OwnerUserId IS NOT NULL
      AND v.UserId != p.OwnerUserId -- Vote on someone else's post
      AND v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year' -- Recent voting activity
    GROUP BY v.UserId
    HAVING COUNT(v.Id) >= 5 -- User has made at least 5 votes on others' posts
),
AllRelevantUsers AS (
    -- Pre-filter users based on general criteria for relevance
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.Location,
        u.AboutMe
    FROM Users u
    WHERE u.Reputation >= 1000 -- Established users
      AND u.CreationDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' -- Active for at least 1 year
      AND u.AboutMe IS NOT NULL -- Profile has 'AboutMe' content
)
SELECT
    aru.UserId,
    aru.DisplayName,
    aru.Reputation,
    aru.Location,
    aru.CreationDate AS UserCreationDate,
    aru.Views AS UserProfileViews,
    aru.UpVotes AS UserTotalUpVotes,
    aru.DownVotes AS UserTotalDownVotes,
    tbg.TopBadgeName,
    tbg.TopBadgeClass,
    pes.TotalRecentPosts,
    pes.AvgRecentPostScore,
    pes.TotalRecentPostCommentCount,
    pes.TotalRecentCommentsMade,
    pes.MaxDaysSinceLastActivity,
    pes.AnswerQuestionRatio,
    cva.VotesOnOthersPosts,
    cva.UpVotesOnOthersPosts,
    cva.DownVotesOnOthersPosts,
    -- Correlated subquery to fetch the title of the user's most recent question
    (
        SELECT p_inner.Title
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = aru.UserId
          AND p_inner.PostTypeId = 1
          AND p_inner.Title IS NOT NULL
        ORDER BY p_inner.CreationDate DESC
        LIMIT 1
    ) AS MostRecentQuestionTitle,
    -- Categorize user based on their specific contributions and activity patterns
    CASE
        WHEN cva.VotesOnOthersPosts IS NOT NULL AND pes.AnswerQuestionRatio > 1.5 THEN 'Answer-focused & Community Engaged'
        WHEN cdqc.UserId IS NOT NULL AND aru.Reputation > 5000 THEN 'Experienced Questioner, Duped'
        WHEN hsaa.UserId IS NOT NULL AND pes.TotalRecentCommentsMade >= 50 THEN 'High-Impact Answerer & Active Commenter'
        WHEN aru.DownVotes > aru.UpVotes * 0.5 THEN 'Potentially Controversial' -- Example of more complex logic
        ELSE 'General Contributor'
    END AS UserCategory,
    -- Check if the user has asked recent questions tagged with both 'database' and 'sql'
    EXISTS (
        SELECT 1
        FROM Posts p_tags
        WHERE p_tags.OwnerUserId = aru.UserId
          AND p_tags.PostTypeId = 1
          AND p_tags.Tags LIKE '%<database>%'
          AND p_tags.Tags LIKE '%<sql>%'
          AND p_tags.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    ) AS HasRecentDatabaseSQLQuestions,
    -- String manipulation: Provide a shortened preview of the 'AboutMe' text
    CASE
        WHEN aru.AboutMe IS NOT NULL AND LENGTH(aru.AboutMe) > 150
        THEN SUBSTRING(aru.AboutMe, 1, 147) || '...'
        ELSE aru.AboutMe
    END AS ShortAboutMePreview,
    -- NULL logic: Provide a default string for unknown locations
    COALESCE(aru.Location, 'Unknown Location') AS UserLocationDetail,
    -- Window function: Rank users by reputation within their known location, handling NULL locations by grouping them together
    ROW_NUMBER() OVER (PARTITION BY COALESCE(aru.Location, 'N/A') ORDER BY aru.Reputation DESC, aru.CreationDate ASC) AS RankInLocation
FROM AllRelevantUsers aru
LEFT JOIN UserDuplicateQuestionClosures cdqc ON aru.UserId = cdqc.UserId
LEFT JOIN HighScoreAcceptedAnswers hsaa ON aru.UserId = hsaa.UserId
LEFT JOIN UserTopBadge tbg ON aru.UserId = tbg.UserId
LEFT JOIN UserPostEngagementSummary pes ON aru.UserId = pes.UserId
LEFT JOIN CrossUserVotingActivity cva ON aru.UserId = cva.UserId
WHERE
    (cdqc.UserId IS NOT NULL OR hsaa.UserId IS NOT NULL) -- User must meet at least one of the primary criteria
    AND aru.Reputation >= 2000 -- Stricter reputation filter for final selection
    AND (pes.AvgRecentPostScore IS NULL OR pes.AvgRecentPostScore > 10) -- Ensure some quality in recent posts, or no recent posts
    AND (cva.VotesOnOthersPosts IS NULL OR cva.VotesOnOthersPosts > 10) -- More specific filter on community voting activity
    AND aru.Location IS NOT NULL -- Only include users with a specified location
    AND (
        (pes.TotalRecentPosts > 5 AND pes.TotalRecentCommentsMade > 10) -- Active contributors
        OR (aru.Views > 500 AND aru.UpVotes > 100) -- Influential users
    )
ORDER BY
    aru.Reputation DESC,
    COALESCE(pes.MaxDaysSinceLastActivity, 99999) ASC, -- Sort by most recent activity
    aru.CreationDate ASC
LIMIT 1000;