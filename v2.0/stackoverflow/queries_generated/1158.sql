-- {"query": "1158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3124} 

WITH UserActivitySummary AS (
    -- CTE 1: Aggregates user activity, including post counts, comment counts, history events, and badge classes.
    -- Calculates user's upvote to downvote ratio and average post score, handling NULLs.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName AS UserDisplayName,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Calculate user's upvote to downvote ratio, preventing division by zero
        CAST(u.UpVotes AS NUMERIC) / NULLIF(u.DownVotes, 0) AS UpDownVoteRatio,
        -- Calculate average score of user's posts, excluding NULL scores
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.UpVotes, u.DownVotes
    HAVING
        COUNT(DISTINCT p.Id) > 5 -- Only consider users with more than 5 posts
        AND u.Reputation > 500 -- Minimum reputation threshold
),
QuestionDetailedMetrics AS (
    -- CTE 2: Provides detailed metrics for questions, including accepted answer status, view counts, and editor activity.
    -- Uses correlated subquery to count comments made after the last activity date.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastActivityDate,
        q.Title AS QuestionTitle,
        q.Tags AS RawTags,
        -- Use COALESCE to provide a default for AcceptedAnswerId if NULL
        COALESCE(q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        -- Count of distinct users (excluding the owner) who have edited the post
        COUNT(DISTINCT CASE WHEN ph_editors.UserId IS NOT NULL AND ph_editors.UserId <> q.OwnerUserId THEN ph_editors.UserId END) AS OtherEditorCount,
        -- Check if the question has any "Post Closed" history event
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS HasBeenClosed,
        -- Date of the latest 'Edit Body' history event for the question
        MAX(CASE WHEN ph_body_edit.PostHistoryTypeId = 5 THEN ph_body_edit.CreationDate ELSE NULL END) AS LastBodyEditDate,
        -- Average score of answers to this specific question, ignoring NULL scores
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        -- Correlated subquery: Count comments made after the question's last activity date
        (SELECT COUNT(c_sub.Id) FROM Comments c_sub WHERE c_sub.PostId = q.Id AND c_sub.CreationDate > q.LastActivityDate) AS CommentsAfterLastActivity
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2 -- LEFT JOIN to include questions without answers
    LEFT JOIN PostHistory ph_editors ON q.Id = ph_editors.PostId AND ph_editors.PostHistoryTypeId IN (4, 5, 6) -- Editors: title, body, tags
    LEFT JOIN PostHistory ph_close ON q.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed event
    LEFT JOIN PostHistory ph_body_edit ON q.Id = ph_body_edit.PostId AND ph_body_edit.PostHistoryTypeId = 5 -- Body edit event
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY
        q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
        q.FavoriteCount, q.ClosedDate, q.LastActivityDate, q.Title, q.Tags, q.AcceptedAnswerId
),
PostTagParsing AS (
    -- CTE 3: Parses the 'Tags' string into individual tag names for each question.
    -- Uses string manipulation and UNNEST (PostgreSQL specific) to handle array conversion.
    SELECT
        QuestionId,
        UNNEST(string_to_array(SUBSTRING(RawTags FROM 2 FOR LENGTH(RawTags) - 2), '><')) AS TagName
    FROM QuestionDetailedMetrics
    WHERE RawTags IS NOT NULL AND LENGTH(RawTags) > 2
),
PostHistoryTimeline AS (
    -- CTE 4: Provides a timeline of post history events, including sequence and type of events.
    -- Uses LAG and LEAD window functions to compare sequential events.
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_event,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        LEAD(pht.Name, 1, 'NoNextEvent') OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEventType,
        (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)) AS TimeSincePreviousEvent
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
)
-- Main Query: Combines user activity, question metrics, and history to identify high-quality questions
-- from engaged users with specific tag interests, and analyzes their evolution.
SELECT
    uas.UserDisplayName,
    uas.Reputation,
    uas.GoldBadges,
    uas.TotalQuestions,
    q.QuestionTitle,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    -- Custom "Question Quality Score" calculation
    (q.QuestionScore * 0.7 + q.ViewCount * 0.05 + q.AnswerCount * 3 + q.FavoriteCount * 5 + COALESCE(q.AvgAnswerScore, 0) * 1.5) AS QuestionQualityScore,
    q.HasBeenClosed,
    q.OtherEditorCount,
    q.AvgAnswerScore,
    q.CommentsAfterLastActivity,
    ph_latest_body_edit.HistoryDate AS LatestBodyEditTimestamp,
    ph_latest_body_edit.HistoryUserId AS LatestBodyEditorId,
    ph_latest_any_edit.HistoryDate AS LatestAnyEditTimestamp,
    ph_latest_any_edit.HistoryTypeName AS LatestAnyEditType,
    t.TagName AS PrimaryQuestionTag,
    -- Determine the score of the accepted answer, or 0 if none
    COALESCE((SELECT ans.Score FROM Posts ans WHERE ans.Id = q.AcceptedAnswerId), 0) AS AcceptedAnswerScore,
    -- Calculate days a question has been open until closure or current date
    EXTRACT(DAY FROM (COALESCE(q.ClosedDate, CURRENT_TIMESTAMP) - q.QuestionCreationDate)) AS DaysOpenSinceCreation,
    -- Categorize user based on reputation and badges using a CASE expression
    CASE
        WHEN uas.Reputation >= 20000 AND uas.GoldBadges >= 5 THEN 'Elite Influencer'
        WHEN uas.Reputation >= 10000 AND uas.SilverBadges >= 10 THEN 'Senior Contributor'
        WHEN uas.Reputation >= 5000 AND uas.BronzeBadges >= 20 THEN 'Active Community Member'
        ELSE 'General Participant'
    END AS UserEngagementTier,
    -- Correlated subquery: Check if the user has a specific named badge ('Great Question')
    (SELECT COUNT(b_sub.Id) FROM Badges b_sub WHERE b_sub.UserId = uas.UserId AND b_sub.Name = 'Great Question') > 0 AS HasGreatQuestionBadge,
    -- Use set operators (UNION ALL) aggregated into a string for related posts (original and duplicates)
    (
        SELECT STRING_AGG(
            CASE
                WHEN related_post_type = 'Original' THEN 'Original: ' || p_rel.Title || ' (ID: ' || p_rel.Id || ')'
                ELSE 'Duplicate Of: ' || p_rel.Title || ' (ID: ' || p_rel.Id || ')'
            END, '; ' ORDER BY related_post_type DESC
        )
        FROM (
            SELECT 'Original' AS related_post_type, p_orig.Title, p_orig.Id
            FROM Posts p_orig
            WHERE p_orig.Id = q.QuestionId
            UNION ALL
            SELECT 'Duplicate Of' AS related_post_type, p_dup.Title, p_dup.Id
            FROM PostLinks pl
            JOIN Posts p_dup ON pl.RelatedPostId = p_dup.Id
            WHERE pl.PostId = q.QuestionId AND pl.LinkTypeId = 3
        ) AS sub_related_posts
    ) AS RelatedPostsSummary,
    -- Time since the latest activity in hours, using NULL logic
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - q.LastActivityDate)) / 3600 AS HoursSinceLastActivity
FROM UserActivitySummary uas
JOIN QuestionDetailedMetrics q ON uas.UserId = q.OwnerUserId
LEFT JOIN (
    -- Select a primary tag for each question, prioritizing specific technical tags
    SELECT PostId, TagName
    FROM PostTagParsing
    QUALIFY ROW_NUMBER() OVER (PARTITION BY QuestionId ORDER BY
        CASE WHEN TagName IN ('sql', 'database', 'performance', 'query-optimization', 'data-modeling') THEN 0 ELSE 1 END,
        TagName
    ) = 1
) t ON q.QuestionId = t.PostId
LEFT JOIN (
    -- Get the latest "Edit Body" history entry for each post
    SELECT ph.PostId, ph.CreationDate AS HistoryDate, ph.UserId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5 -- Edit Body
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) = 1
) AS ph_latest_body_edit ON q.QuestionId = ph_latest_body_edit.PostId
LEFT JOIN (
    -- Get the latest ANY edit history entry (title, body, tags) for each post
    SELECT ph.PostId, ph.CreationDate AS HistoryDate, pht.Name AS HistoryTypeName
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) = 1
) AS ph_latest_any_edit ON q.QuestionId = ph_latest_any_edit.PostId
WHERE
    q.QuestionScore > 15
    AND q.ViewCount > 500
    AND q.LastBodyEditDate IS NOT NULL -- Ensure the question has at least one body edit
    AND t.TagName IN ('sql', 'database', 'performance', 'query-optimization') -- Filter by specific technical tags
    AND uas.TotalQuestions > 10
    AND uas.UpDownVoteRatio > 3.0 -- Require a good upvote to downvote ratio for the user
    -- Complex NULL and existence logic: user must have at least one Gold badge OR total reputation > 15000 AND not closed
    AND (EXISTS (SELECT 1 FROM Badges b_inner WHERE b_inner.UserId = uas.UserId AND b_inner.Class = 1) OR uas.Reputation > 15000)
    AND q.HasBeenClosed = 0 -- Exclude closed questions
    AND q.FavoriteCount > 2 -- Questions must be favorited a few times
    AND (CURRENT_TIMESTAMP - q.LastActivityDate) < INTERVAL '30 days' -- Activity within the last 30 days
ORDER BY
    QuestionQualityScore DESC, uas.Reputation DESC, q.LastActivityDate DESC
LIMIT 200;
