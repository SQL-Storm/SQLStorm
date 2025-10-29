-- {"query": "1733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3834} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT p_ans.Id) FILTER (WHERE p_ans.PostTypeId = 2) AS TotalAnswersGiven,
        -- Count unique questions where this user's answer was accepted
        COUNT(DISTINCT q.Id) FILTER (WHERE q.AcceptedAnswerId IN (SELECT pa.Id FROM Posts pa WHERE pa.OwnerUserId = u.Id AND pa.PostTypeId = 2)) AS AcceptedAnswersCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        -- Correlated subquery: Check if user has ever posted an answer for a highly viewed question (>= 100k views)
        EXISTS (
            SELECT 1
            FROM Posts sq_p_ans
            WHERE sq_p_ans.OwnerUserId = u.Id
              AND sq_p_ans.PostTypeId = 2
              AND sq_p_ans.ParentId IS NOT NULL
              AND (SELECT sq_q.ViewCount FROM Posts sq_q WHERE sq_q.Id = sq_p_ans.ParentId) >= 100000
            LIMIT 1
        ) AS HasAnsweredPopularQuestion,
        -- Window function: Calculate the average number of days users in the same creation year cohort remain active (based on last access)
        AVG(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0)
            OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AvgUserLifetimeDaysInCohort,
        -- Correlated subquery: Get the most recent comment made by this user, if any
        (
            SELECT sq_c.Text
            FROM Comments sq_c
            WHERE sq_c.UserId = u.Id
            ORDER BY sq_c.CreationDate DESC
            LIMIT 1
        ) AS LatestCommentText
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p_ans ON u.Id = p_ans.OwnerUserId AND p_ans.PostTypeId = 2 -- Only answers owned by user
    LEFT JOIN Posts q ON q.PostTypeId = 1 -- Questions to check for accepted answers
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        -- Use COALESCE to get an effective closed date, preferring Posts.ClosedDate then PostHistory (type 10)
        COALESCE(p.ClosedDate, ph_closed.CreationDate) AS EffectiveClosedDate,
        -- String expression: Extract the first tag if available, else 'Untagged'
        COALESCE(
            TRIM(SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2)),
            'Untagged'
        ) AS FirstTag,
        -- Complicated calculation: engagement ratio per hour since creation or last activity
        (p.Score * 2.0 + p.ViewCount * 0.1 + COALESCE(p.FavoriteCount, 0) * 3 + COALESCE(p.AnswerCount, 0) * 5 + COALESCE(p.CommentCount, 0) * 1)
        / NULLIF(EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600.0, 0) AS EngagementRatioPerHour,
        -- Window function: Rank posts by score within their respective PostType and creation month
        RANK() OVER (PARTITION BY p.PostTypeId, EXTRACT(MONTH FROM p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreInMonth,
        -- Correlated subquery: Check if this post has any associated duplicate links (LinkTypeId = 3)
        EXISTS (
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3 LIMIT 1
        ) AS HasDuplicateLinks,
        -- Correlated subquery: Get the PostHistoryTypeId of the most common non-trivial edit/event for this post
        (
            SELECT ph_type.PostHistoryTypeId
            FROM PostHistory ph_type
            WHERE ph_type.PostId = p.Id
              AND ph_type.PostHistoryTypeId NOT IN (1, 2, 3, 16) -- Exclude initial title/body/tags, community owned
            GROUP BY ph_type.PostHistoryTypeId
            ORDER BY COUNT(*) DESC, ph_type.PostHistoryTypeId DESC
            LIMIT 1
        ) AS MostCommonHistoryType,
        -- NULL logic: determine if a post is an accepted question, otherwise NULL
        NULLIF(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END, FALSE) AS IsAcceptedQuestion,
        -- String expression: Cleaned title for display, replacing common delimiters and handling NULL
        COALESCE(REPLACE(REPLACE(p.Title, ' ', '_'), '-', '_'), 'Untitled_Post_' || p.Id) AS CleanedTitle
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN ( -- Subquery to find the latest closed date from PostHistory
        SELECT ph.PostId, MAX(ph.CreationDate) AS CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10 -- Post Closed
        GROUP BY ph.PostId
    ) AS ph_closed ON p.Id = ph_closed.PostId
    WHERE p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
),
PostCommentActivity AS (
    SELECT
        pde.PostId,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        -- Window function: Calculate cumulative average comment score for posts by the same owner, ordered by post creation date
        AVG(AVG(c.Score)) OVER (PARTITION BY pde.OwnerUserId ORDER BY pde.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAvgCommentScoreForOwner
    FROM PostDetailsExtended pde
    JOIN Comments c ON pde.PostId = c.PostId
    GROUP BY pde.PostId, pde.OwnerUserId, pde.PostCreationDate
),
TagUsageStats AS (
    SELECT
        EXTRACT(YEAR FROM p.CreationDate) AS PostYear,
        tag_exploded.tag AS TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.Score) AS AvgTagScore,
        -- Window function: Calculate percentage of posts with this tag out of all questions in the specific year
        (COUNT(DISTINCT p.Id) * 100.0) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) /
        NULLIF(COUNT(DISTINCT p.Id) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY 1), 0) AS TagPostsPercentageInYear,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS TagRankByScoreInYear
    FROM Posts p,
         LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_exploded(tag)
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY EXTRACT(YEAR FROM p.CreationDate), tag_exploded.tag
),
UserTopTag AS (
    -- CTE to determine each user's top performing tag based on average score of their questions
    SELECT
        p.OwnerUserId AS UserId,
        tag_exploded.tag AS TagName,
        AVG(p.Score) AS AvgTagScore,
        COUNT(p.Id) AS TaggedPostsCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY AVG(p.Score) DESC, COUNT(p.Id) DESC) AS rn
    FROM Posts p,
         LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_exploded(tag)
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag_exploded.tag
)
-- Main Query combining user engagement and post details
SELECT
    'HighEngagementUser' AS ProfileType,
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPostsOwned,
    ue.TotalAnswersGiven,
    ue.AcceptedAnswersCount,
    pde.PostId,
    pde.PostTypeName,
    pde.PostScore,
    pde.EngagementRatioPerHour,
    pde.RankByScoreInMonth,
    pca.AvgCommentScore,
    utt.TagName AS TopContributingTag,
    utt.AvgTagScore AS TopTagAvgScore,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    -- Complicated calculation for overall performance score
    (ue.Reputation * 0.1 + ue.TotalPostsOwned * 5 + ue.AcceptedAnswersCount * 10 + ue.TotalBadges * 2 + COALESCE(pde.EngagementRatioPerHour, 0) * 100 + COALESCE(pca.AvgCommentScore, 0) * 5) AS OverallPerformanceScore,
    -- String expression with NULL logic for a formatted user identifier
    COALESCE(ue.DisplayName, 'Anonymous User #' || ue.UserId) || ' (Posts: ' || ue.TotalPostsOwned || ', Badges: ' || ue.TotalBadges || ')' AS FormattedUserIdentifier,
    -- NULL-aware calculation for answer acceptance rate
    NULLIF(ue.AcceptedAnswersCount, 0) * 100.0 / NULLIF(ue.TotalAnswersGiven, 0) AS AnswerAcceptanceRate,
    -- Date difference (in days)
    EXTRACT(DAY FROM (ue.LastAccessDate - ue.UserCreationDate)) AS DaysActiveSinceCreation,
    pde.FirstTag,
    pde.HasDuplicateLinks,
    pde.IsAcceptedQuestion,
    pde.CleanedTitle,
    ue.LatestCommentText -- The correlated subquery result
FROM UserEngagement ue
JOIN PostDetailsExtended pde ON ue.UserId = pde.OwnerUserId
LEFT JOIN PostCommentActivity pca ON pde.PostId = pca.PostId
LEFT JOIN UserTopTag utt ON ue.UserId = utt.UserId AND utt.rn = 1
WHERE
    ue.Reputation >= 1000
    AND ue.TotalPostsOwned >= 5
    AND pde.EngagementRatioPerHour IS NOT NULL
    AND pde.PostTypeName = 'Question'
    AND pde.HasDuplicateLinks = FALSE
    AND ue.HasAnsweredPopularQuestion = TRUE
    AND pde.EffectiveClosedDate IS NULL -- Only open questions
    AND ue.AvgUserLifetimeDaysInCohort > 30 -- Filter for users with a reasonable activity span
    AND COALESCE(utt.AvgTagScore, 0) >= 10 -- Only if their top tag has a decent average score
    AND pde.CleanedTitle ILIKE '%sql_%query%' -- Case-insensitive search for specific terms in cleaned title
    AND NOT EXISTS ( -- Correlated subquery: Exclude users who have posted any offensive votes
        SELECT 1 FROM Votes v WHERE v.UserId = ue.UserId AND v.VoteTypeId = 4
    )
UNION ALL
-- Second branch: Focus on active editors and their contributions
SELECT
    'ActiveEditor' AS ProfileType,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    NULL AS TotalPostsOwned, -- Not primary focus for editors, can be NULL
    NULL AS TotalAnswersGiven,
    NULL AS AcceptedAnswersCount,
    ph.PostId,
    pt.Name AS PostTypeName,
    p.Score AS PostScore,
    NULL AS EngagementRatioPerHour, -- Not directly calculated for editors in this context
    NULL AS RankByScoreInMonth,
    NULL AS AvgCommentScore,
    NULL AS TopContributingTag,
    NULL AS TopTagAvgScore,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    -- Complicated calculation for editors' overall performance score, weighted by edit types
    (u.Reputation * 0.05 + COUNT(ph.Id) * 1.5 +
     SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) * 2 + -- Edit types
     SUM(CASE WHEN ph.PostHistoryTypeId IN (8,9) THEN 1 ELSE 0 END) * 3) AS OverallPerformanceScore, -- Rollback types
    -- String expression with NULL logic for a formatted editor identifier
    COALESCE(u.DisplayName, 'Anonymous Editor ID:' || u.Id) || ' (Edits: ' || COUNT(ph.Id) || ')' AS FormattedUserIdentifier,
    NULL AS AnswerAcceptanceRate,
    EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) AS DaysActiveSinceCreation,
    NULL AS FirstTag,
    NULL AS HasDuplicateLinks,
    NULL AS IsAcceptedQuestion,
    COALESCE(REPLACE(REPLACE(p.Title, ' ', '_'), '-', '_'), 'Edited_Post_' || p.Id) AS CleanedTitle,
    NULL AS LatestCommentText
FROM Users u
JOIN PostHistory ph ON u.Id = ph.UserId
JOIN Posts p ON ph.PostId = p.Id
JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE
    ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11) -- Edit Title, Body, Tags, Rollback Body/Tags, Post Closed/Reopened
    AND u.Reputation >= 500
    AND ph.CreationDate >= '2022-01-01'
    AND NOT EXISTS ( -- Correlated subquery: Exclude editors who have never edited a 'Question'
        SELECT 1 FROM PostHistory sq_ph_q JOIN Posts sq_p_q ON sq_ph_q.PostId = sq_p_q.Id WHERE sq_ph_q.UserId = u.Id AND sq_p_q.PostTypeId = 1 AND sq_ph_q.PostHistoryTypeId IN (4,5,6)
    )
GROUP BY
    u.Id, u.DisplayName, u.Reputation, ph.PostId, pt.Name, p.Score, u.CreationDate, u.LastAccessDate, p.Title
HAVING
    COUNT(ph.Id) >= 5 -- At least 5 edits/post history actions
    AND SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) >= 1 -- At least one actual edit
ORDER BY
    OverallPerformanceScore DESC, Reputation DESC
LIMIT 500;
