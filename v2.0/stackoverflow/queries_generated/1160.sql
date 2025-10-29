-- {"query": "1160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3178} 
WITH PostMetadata AS (
    -- Base CTE to extract core post attributes, parse tags, and calculate post age.
    -- Filters for PostTypeId = 1 (Questions) to simplify subsequent joins.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.ClosedDate,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / (3600.0 * 24.0) AS PostAgeDays, -- Post age in days
        string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS ParsedTags -- Converts '><tag1><tag2>' into an array of tags
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
),
PostActivitySummary AS (
    -- Aggregates various historical activities for each post from PostHistory table.
    -- Counts edits, close/reopen events, and tracks first/last moderation dates.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS UniqueEditorsOrModerators,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- 4=Edit Title, 5=Edit Body, 6=Edit Tags
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount, -- 10=Post Closed
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount, -- 11=Post Reopened
        SUM(CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS DeleteUndeleteCount, -- 12=Post Deleted, 13=Post Undeleted
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
        MIN(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS FirstReopenedDate
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY
        ph.PostId
),
PostVoteAndCommentMetrics AS (
    -- Aggregates upvotes, downvotes, favorites from Votes, and comment statistics from Comments.
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes, -- 2=UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes, -- 3=DownMod
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites, -- 5=Favorite
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(c.Score) AS AverageCommentScore,
        COUNT(c.Id) AS TotalComments
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id
),
UserEngagementStats AS (
    -- Aggregates user-specific statistics like reputation, badge counts, and total posts by type.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.CreationDate AS UserCreationDate,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsByOwner,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersByOwner
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
QuestionDetailedMetrics AS (
    -- Combines all previous CTEs and adds further calculations and correlated subqueries.
    SELECT
        pm.PostId,
        pm.OwnerUserId,
        pm.Title,
        pm.Body,
        pm.CreationDate AS QuestionCreationDate,
        pm.PostAgeDays,
        pm.Score AS InitialScore,
        pm.ViewCount,
        pm.AnswerCount,
        pm.CommentCount AS InitialCommentCount,
        pm.FavoriteCount AS InitialFavoriteCount,
        pm.ParsedTags,
        uas.Reputation AS OwnerReputation,
        uas.UserViews,
        uas.GoldBadges AS OwnerGoldBadges,
        uas.TotalQuestionsByOwner,
        pas.EditCount,
        pas.CloseEventCount,
        pas.ReopenEventCount,
        pas.DeleteUndeleteCount,
        pas.LastClosedDate,
        pas.FirstReopenedDate,
        pvcm.Upvotes,
        pvcm.Downvotes,
        pvcm.Favorites,
        pvcm.TotalComments,
        pvcm.UniqueCommenters,
        pvcm.AverageCommentScore,
        NULLIF(pvcm.Upvotes + pvcm.Downvotes, 0) AS TotalVotes, -- Avoid division by zero
        (pvcm.Upvotes::numeric - pvcm.Downvotes) / NULLIF(pvcm.Upvotes + pvcm.Downvotes, 0) AS NetVoteRatio, -- Ratio of upvotes vs downvotes
        RANK() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.Score DESC, pm.ViewCount DESC) AS OwnerPostRankByScoreViews, -- Ranks owner's posts
        LAG(pm.CreationDate, 1) OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CreationDate) AS PrevQuestionDateByOwner, -- Date of previous question by the same owner
        COUNT(pm.PostId) OVER (PARTITION BY pm.OwnerUserId) AS TotalOwnerQuestions,
        COALESCE(pm.ClosedDate, pas.LastClosedDate) IS NOT NULL AS IsClosed, -- Uses NULL logic
        LOWER(pm.Title) LIKE '%error%' OR LOWER(pm.Title) LIKE '%bug%' AS HasProblemKeywordInTitle, -- String expression
        -- Correlated subquery 1: Checks if any of the post's direct answers have been accepted by an existing user.
        (SELECT EXISTS (
            SELECT 1
            FROM Posts pa
            WHERE pa.ParentId = pm.PostId
              AND pa.Id = (SELECT p_q.AcceptedAnswerId FROM Posts p_q WHERE p_q.Id = pm.PostId)
              AND pa.OwnerUserId IS NOT NULL
        )) AS HasAcceptedAnswerByExistingUser,
        -- Correlated subquery 2: Checks if any editor of this question has a gold badge related to one of its tags.
        (SELECT EXISTS (
            SELECT 1
            FROM PostHistory ph_editor
            JOIN Badges b_editor ON ph_editor.UserId = b_editor.UserId
            WHERE ph_editor.PostId = pm.PostId
              AND ph_editor.PostHistoryTypeId IN (4, 5, 6) -- Edit events
              AND b_editor.Class = 1 -- Gold badge
              AND b_editor.TagBased = TRUE
              AND b_editor.Name IS NOT NULL
              AND EXISTS (SELECT 1 FROM unnest(pm.ParsedTags) AS post_tag WHERE post_tag = b_editor.Name) -- Checks if badge name matches any of the post's tags
        )) AS EditedByTagGoldBadger
    FROM
        PostMetadata pm
    LEFT JOIN
        PostActivitySummary pas ON pm.PostId = pas.PostId
    LEFT JOIN
        PostVoteAndCommentMetrics pvcm ON pm.PostId = pvcm.PostId
    LEFT JOIN
        UserEngagementStats uas ON pm.OwnerUserId = uas.UserId
    WHERE
        pm.OwnerUserId IS NOT NULL AND uas.Reputation > 500
        AND LENGTH(pm.Body) > 500 -- Filters for substantial question bodies
        AND pm.ParsedTags IS NOT NULL AND array_length(pm.ParsedTags, 1) > 0 -- Ensures tags exist
)
-- Branch 1: Highly Edited and/or Moderated Questions
-- Focuses on questions with significant editing activity, moderation events, and experienced owners.
SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.QuestionCreationDate,
    q.PostAgeDays,
    q.Upvotes,
    q.Downvotes,
    q.Favorites,
    q.TotalComments,
    q.EditCount,
    q.CloseEventCount,
    q.ReopenEventCount,
    q.NetVoteRatio,
    q.IsClosed,
    q.HasProblemKeywordInTitle,
    q.ParsedTags,
    q.OwnerPostRankByScoreViews,
    (q.TotalOwnerQuestions > 1 AND AGE(q.QuestionCreationDate, q.PrevQuestionDateByOwner) < INTERVAL '30 days') AS OwnerFrequentPoster, -- Boolean check for owner posting frequently
    q.HasAcceptedAnswerByExistingUser,
    q.EditedByTagGoldBadger,
    'Highly Edited/Moderated' AS QuestionHighlightType,
    -- Window function: Average edit count for owners within specific high reputation ranges.
    AVG(q.EditCount) OVER (PARTITION BY floor(q.OwnerReputation / 5000) * 5000) AS AvgEditCountByHighRepRange,
    -- String expression and NULL handling: Extracts the first word from the title, handles NULLs.
    COALESCE(
        LEFT(q.Title, POSITION(' ' IN q.Title) - 1),
        q.Title,
        'NoTitle'
    ) AS FirstWordInTitle
FROM
    QuestionDetailedMetrics q
WHERE
    q.PostAgeDays > 60 -- Only posts older than 60 days
    AND q.TotalComments > 10 -- With at least 10 comments
    AND q.EditCount > 5 -- Edited more than 5 times
    AND (q.CloseEventCount > 0 OR q.ReopenEventCount > 0) -- Has been closed or reopened
    AND q.OwnerReputation > 1000 -- Owner has a good reputation
    AND q.EditedByTagGoldBadger = TRUE -- Filter for questions edited by a gold tag badger
UNION ALL
-- Branch 2: Highly Voted and/or Controversial Questions
-- Focuses on questions with significant up/down votes, potential controversy, and an accepted answer.
SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.QuestionCreationDate,
    q.PostAgeDays,
    q.Upvotes,
    q.Downvotes,
    q.Favorites,
    q.TotalComments,
    q.EditCount,
    q.CloseEventCount,
    q.ReopenEventCount,
    q.NetVoteRatio,
    q.IsClosed,
    q.HasProblemKeywordInTitle,
    q.ParsedTags,
    q.OwnerPostRankByScoreViews,
    (q.TotalOwnerQuestions > 1 AND AGE(q.QuestionCreationDate, q.PrevQuestionDateByOwner) < INTERVAL '30 days') AS OwnerFrequentPoster,
    q.HasAcceptedAnswerByExistingUser,
    q.EditedByTagGoldBadger,
    'Highly Voted/Controversial' AS QuestionHighlightType,
    -- Window function: Average net vote ratio partitioned by whether the title contains 'problem' or 'bug'.
    AVG(q.NetVoteRatio) OVER (PARTITION BY q.HasProblemKeywordInTitle) AS AvgNetVoteRatioByProblematicTitle,
    COALESCE(
        LEFT(q.Title, POSITION(' ' IN q.Title) - 1),
        q.Title,
        'NoTitle'
    ) AS FirstWordInTitle
FROM
    QuestionDetailedMetrics q
WHERE
    q.PostAgeDays > 30 -- Only posts older than 30 days
    AND q.Upvotes > 100 -- High number of upvotes
    AND q.Downvotes > 10 -- But also some downvotes (indicating potential controversy)
    AND (q.NetVoteRatio < 0.7 OR q.Favorites > 20) -- Either somewhat controversial or very popular
    AND q.HasAcceptedAnswerByExistingUser = TRUE -- Must have an accepted answer
    AND q.OwnerReputation > 750 -- Owner has a decent reputation
ORDER BY
    QuestionCreationDate DESC, Upvotes DESC
LIMIT 2000; -- Limits the total combined result set