-- {"query": "1821.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3092} 
WITH UserActivitySummary AS (
    -- Summarizes various user activities including post creation, comments, and post edits.
    -- Includes a calculation for the last known edit activity date by the user.
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph_edit.PostId) AS DistinctPostsEdited,
        SUM(CASE WHEN ph_edit.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        MAX(ph_edit.CreationDate) AS LastPostEditActivityDate,
        MAX(u.LastAccessDate) AS LastAccessDateSummary
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph_edit ON u.Id = ph_edit.UserId AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY u.Id
),
QuestionPerformance AS (
    -- Analyzes performance metrics for questions, including scores, views, answer acceptance,
    -- and interaction counts like upvoters and commenters, plus linked posts.
    -- Uses a correlated subquery for UpvotersCount and CommentersCount.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionCreationDate,
        q.AcceptedAnswerId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS TimeToAcceptAnswerHours, -- Time difference calculation
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpvotersCount,
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = q.Id) AS CommentersCount,
        (SELECT COUNT(pl.Id) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Only questions
    AND q.ViewCount > 0
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2 -- Accepted answers (Outer Join)
),
PostHistoryDetails AS (
    -- Extracts specific details from post history, primarily for tracking edit content and close/reopen events.
    -- Uses a window function to identify the latest revision for specific types.
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        ph.Text AS CurrentText,
        LEAD(ph.Text, 1, ph.Text) OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS PreviousText, -- LAG to get previous content
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_latest
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (5, 6, 10, 11) -- Edit Body, Edit Tags, Post Closed, Post Reopened
),
RecentTagChanges AS (
    -- Processes tag changes by splitting string-delimited tags into arrays and comparing current vs previous versions.
    -- Uses `string_to_array` and `LAG` window function.
    SELECT
        ph.PostId,
        ph.CreationDate AS TagEditDate,
        ph.UserId AS EditorId,
        string_to_array(SUBSTRING(ph.Text, 2, LENGTH(ph.Text) - 2), '><') AS CurrentTagsArray,
        string_to_array(SUBSTRING(LAG(ph.Text, 1, ph.Text) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate), 2, LENGTH(LAG(ph.Text, 1, ph.Text) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)) - 2), '><') AS PreviousTagsArray
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 6 -- Edit Tags
    AND ph.Text IS NOT NULL AND LENGTH(ph.Text) > 2 -- Ensure valid tag string
),
SignificantTagChanges AS (
    -- Identifies actual tags added or removed in the most recent tag edit for a post.
    -- Utilizes set operators (`EXCEPT` on unnested arrays) for sophisticated array comparison.
    SELECT
        rtc.PostId,
        rtc.EditorId,
        rtc.TagEditDate,
        ARRAY_TO_STRING(ARRAY(SELECT UNNEST(rtc.CurrentTagsArray) EXCEPT SELECT UNNEST(rtc.PreviousTagsArray)), ', ') AS AddedTags,
        ARRAY_TO_STRING(ARRAY(SELECT UNNEST(rtc.PreviousTagsArray) EXCEPT SELECT UNNEST(rtc.CurrentTagsArray)), ', ') AS RemovedTags
    FROM RecentTagChanges rtc
    WHERE rtc.TagEditDate = (SELECT MAX(TagEditDate) FROM RecentTagChanges WHERE PostId = rtc.PostId) -- Most recent tag edit
)
SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous User') AS UserDisplayName, -- NULL Logic (COALESCE)
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    uas.TotalPosts,
    uas.TotalComments,
    uas.DistinctPostsEdited,
    uas.TotalEdits,
    uas.LastPostEditActivityDate,
    STRING_AGG(DISTINCT b.Name, '; ') FILTER (WHERE b.Class = 1) AS GoldBadges, -- Aggregate with filter (String Expression)
    AVG(qp.QuestionScore * 1.0) AS AvgQuestionScore,
    SUM(CASE WHEN qp.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
    -- Complicated Calculation: Engagement ratio weighted by question score, upvotes, comments, and views.
    SUM(qp.QuestionScore * (qp.UpvotersCount * 0.5 + qp.CommentersCount * 0.75) / NULLIF(qp.ViewCount, 0)) AS EngagementWeightedScore, -- NULL Logic (NULLIF)
    -- Window Function: Ranks users based on their engagement weighted score.
    RANK() OVER (ORDER BY SUM(qp.QuestionScore * (qp.UpvotersCount * 0.5 + qp.CommentersCount * 0.75) / NULLIF(qp.ViewCount, 0)) DESC NULLS LAST) AS EngagementRank,
    -- Correlated Subquery 1: Retrieves the highest score from any answer posted by the current user.
    (
        SELECT COALESCE(MAX(a_user.Score), 0)
        FROM Posts a_user
        WHERE a_user.OwnerUserId = u.Id AND a_user.PostTypeId = 2
    ) AS MaxAnswerScore,
    -- NULL Logic (BOOL_OR) with Correlated Subquery: Checks if the user has edited a post that was later closed and then re-opened.
    BOOL_OR(
        EXISTS (
            SELECT 1
            FROM PostHistoryDetails phd_closed
            WHERE phd_closed.PostId = qp.QuestionId
            AND phd_closed.PostHistoryTypeId = 10 -- Post Closed
            AND phd_closed.HistoryUserId = u.Id
            AND EXISTS (
                SELECT 1
                FROM PostHistoryDetails phd_reopened
                WHERE phd_reopened.PostId = qp.QuestionId
                AND phd_reopened.PostHistoryTypeId = 11 -- Post Reopened
                AND phd_reopened.HistoryDate > phd_closed.HistoryDate
            )
        )
    ) AS EditedAndReopenedPostFlag,
    -- Correlated Subquery 2: Summarizes recent significant tag edits made by the user on their questions.
    -- Uses string concatenation and NULLIF for clean output of added/removed tags.
    (
        SELECT STRING_AGG(
            COALESCE('Added: ' || NULLIF(stc.AddedTags, ''), '') ||
            COALESCE(' Removed: ' || NULLIF(stc.RemovedTags, ''), '')
        , ' | ')
        FROM SignificantTagChanges stc
        WHERE stc.EditorId = u.Id
        AND stc.PostId IN (SELECT qp_inner.QuestionId FROM QuestionPerformance qp_inner WHERE qp_inner.OwnerUserId = u.Id)
        AND stc.TagEditDate >= CURRENT_DATE - INTERVAL '180 days'
        AND (stc.AddedTags IS NOT NULL OR stc.RemovedTags IS NOT NULL)
    ) AS RecentSignificantTagEditsSummary,
    -- Complicated Calculation: Conditional sum based on time to accept answer and question score.
    SUM(CASE
            WHEN qp.TimeToAcceptAnswerHours IS NOT NULL AND qp.TimeToAcceptAnswerHours <= 24 AND qp.QuestionScore > 10 THEN qp.QuestionScore * 2.0
            WHEN qp.TimeToAcceptAnswerHours IS NOT NULL AND qp.TimeToAcceptAnswerHours > 24 AND qp.QuestionScore > 5 THEN qp.QuestionScore * 1.0
            ELSE 0.0
        END) AS TimelyAcceptedHighScoreImpact,
    -- Correlated Subquery 3: Identifies the most frequent tag used by the user in their questions.
    -- Uses `LATERAL UNNEST` to properly parse tags from the `Tags` string column.
    (
        SELECT SUBSTRING(t_tag.TagName, 1, 20)
        FROM Posts p_tag
        JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p_tag.Tags, 2, LENGTH(p_tag.Tags) - 2), '><')) AS unnested_tag(TagName)
        JOIN Tags t_tag ON unnested_tag.TagName = t_tag.TagName
        WHERE p_tag.OwnerUserId = u.Id AND p_tag.PostTypeId = 1 AND p_tag.Tags IS NOT NULL AND LENGTH(p_tag.Tags) > 2
        GROUP BY t_tag.TagName
        ORDER BY COUNT(p_tag.Id) DESC, t_tag.TagName ASC
        LIMIT 1
    ) AS MostFrequentQuestionTag,
    -- Window Function: Calculates the number of days since the previous user in the ranked list was active.
    EXTRACT(DAY FROM (uas.LastAccessDateSummary - LAG(uas.LastAccessDateSummary) OVER (ORDER BY uas.LastAccessDateSummary ASC, u.Id))) AS DaysSincePreviousUserActivity,
    -- Conditional Join with NULL Logic: Determines if the user's last edit was specifically a body edit.
    COALESCE(MAX(CASE WHEN phd_latest_body_edit.PostHistoryTypeId = 5 THEN 'Yes' ELSE 'No' END), 'No') AS LastEditWasBodyEdit,
    -- Average string length of comments made by the user.
    AVG(LENGTH(c_user.Text)) AS AvgCommentLength
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN QuestionPerformance qp ON u.Id = qp.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c_user ON u.Id = c_user.UserId -- Outer Join for comments
LEFT JOIN (
    SELECT PostId, UserId AS HistoryUserId, HistoryDate, PostHistoryTypeId,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY CreationDate DESC) as rn_latest_user_edit
    FROM PostHistory
    WHERE PostHistoryTypeId IN (5, 6) -- Body or Tag edit
) AS phd_latest_body_edit ON u.Id = phd_latest_body_edit.HistoryUserId AND phd_latest_body_edit.rn_latest_user_edit = 1 AND phd_latest_body_edit.PostHistoryTypeId = 5
WHERE u.Reputation >= 1000
  AND uas.TotalPosts > 5
  AND uas.TotalEdits > 2
  AND u.CreationDate <= CURRENT_DATE - INTERVAL '1 year' -- Users active for at least a year
  AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months' -- Recently active users
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    uas.TotalPosts,
    uas.TotalComments,
    uas.DistinctPostsEdited,
    uas.TotalEdits,
    uas.LastPostEditActivityDate,
    uas.LastAccessDateSummary
HAVING SUM(qp.QuestionScore * (qp.UpvotersCount * 0.5 + qp.CommentersCount * 0.75) / NULLIF(qp.ViewCount, 0)) IS NOT NULL
   AND SUM(qp.QuestionScore * (qp.UpvotersCount * 0.5 + qp.CommentersCount * 0.75) / NULLIF(qp.ViewCount, 0)) > 100 -- Filter for meaningful engagement
ORDER BY EngagementRank ASC, u.Reputation DESC
LIMIT 50;