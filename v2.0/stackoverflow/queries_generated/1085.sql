-- {"query": "1085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3865} 

WITH UserActivitySummary AS (
    -- Summarizes user activity including posts, answers accepted, edits made, and overall post performance metrics
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p_all.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p_all.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p_all.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        -- Count questions asked by the user that have an accepted answer
        SUM(CASE WHEN p_all.PostTypeId = 1 AND p_all.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        -- Count answers posted by the user that were accepted by others
        SUM(CASE WHEN p_all.PostTypeId = 2 AND p_all.Id = (SELECT p_q.AcceptedAnswerId FROM Posts p_q WHERE p_q.Id = p_all.ParentId) THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers,
        -- Total number of edit history entries made by the user within a recent period
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        SUM(p_all.Score) AS TotalPostScore,
        SUM(p_all.ViewCount) AS TotalPostViews,
        MAX(p_all.CreationDate) AS LastPostDate,
        MIN(p_all.CreationDate) AS FirstPostDate,
        AVG(CASE WHEN p_all.PostTypeId = 1 THEN p_all.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p_all.PostTypeId = 2 THEN p_all.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM Users u
    LEFT JOIN Posts p_all ON u.Id = p_all.OwnerUserId AND p_all.CreationDate >= (u.CreationDate - INTERVAL '180 days') -- Posts within 180 days of user creation
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6) AND ph.CreationDate >= (u.CreationDate - INTERVAL '180 days')
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= (u.CreationDate - INTERVAL '180 days')
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
TagPerformance AS (
    -- Calculates performance metrics for tags based on associated questions
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, -- Parses the tags string into individual tags
        COUNT(DISTINCT p.Id) AS TotalQuestionsInTag,
        AVG(p.Score) AS AvgQuestionScoreInTag,
        AVG(p.ViewCount) AS AvgQuestionViewsInTag,
        SUM(p.AnswerCount) AS TotalAnswersToTagQuestions,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueQuestionAsk_Users
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only consider questions for tag performance
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2 -- Ensure tags are not empty '><'
    GROUP BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    HAVING COUNT(DISTINCT p.Id) > 50 -- Filter for sufficiently popular tags
),
PostEditMetrics AS (
    -- Analyzes editing patterns for posts, calculating time to first edit and duration of editing activity
    SELECT
        PostId,
        EditCount,
        FirstEditDate,
        LastEditDate,
        InitialPostCreationDate,
        EXTRACT(EPOCH FROM (FirstEditDate - InitialPostCreationDate)) / 3600.0 AS HoursToFirstEdit, -- Time from initial post to first edit in hours
        EXTRACT(EPOCH FROM (LastEditDate - FirstEditDate)) / 3600.0 AS HoursFromFirstToLastEdit -- Duration of editing activity in hours
    FROM (
        SELECT
            ph.PostId,
            COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Count of title/body/tag edits
            MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS FirstEditDate,
            MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastEditDate,
            MIN(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.CreationDate END) AS InitialPostCreationDate -- Initial title/body/tags
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) -- Relevant history types for post creation and edits
        GROUP BY ph.PostId
    ) AS PostAggregatedEdits
    WHERE InitialPostCreationDate IS NOT NULL AND FirstEditDate IS NOT NULL
),
RecentClosedQuestions AS (
    -- Identifies questions that were recently closed and potentially reopened, and their close reasons
    SELECT
        ph.PostId,
        p.Title,
        p.OwnerUserId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        -- Aggregates distinct close reasons into a single string
        STRING_AGG(DISTINCT crt.Name, ' | ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS CloseReasons,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id ELSE NULL END) AS ClosureCount -- Counts how many times a question was closed
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::varchar -- Joins on close reason ID from comment field
    WHERE ph.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
      AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '365 days' -- Within the last year
      AND p.PostTypeId = 1 -- Only questions
    GROUP BY ph.PostId, p.Title, p.OwnerUserId
),
UserBadgeSummary AS (
    -- Gathers information about gold and silver badges for users
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass
    FROM Badges b
    WHERE b.Class IN (1, 2) -- Gold (1) or Silver (2) badges
),
AnomalousPosts AS (
    -- Identifies posts exhibiting potentially anomalous behavior using set operators (UNION ALL)
    -- Anomaly 1: Questions with a high number of edits within a short period after creation
    SELECT p.Id AS PostId, 'HighEditCountFastEdit' AS AnomalyType, p.OwnerUserId
    FROM Posts p
    JOIN PostEditMetrics pem ON p.Id = pem.PostId
    WHERE pem.EditCount > 5 AND EXTRACT(DAY FROM (CURRENT_TIMESTAMP - p.CreationDate)) < 60 -- More than 5 edits within 60 days
      AND pem.HoursToFirstEdit IS NOT NULL AND pem.HoursToFirstEdit < 0.5 -- First edit within 30 minutes of creation

    UNION ALL

    -- Anomaly 2: Questions that were closed multiple times but never reopened
    SELECT rcq.PostId, 'MultipleClosedNoReopen' AS AnomalyType, rcq.OwnerUserId
    FROM RecentClosedQuestions rcq
    WHERE rcq.ClosureCount > 1 AND rcq.LastReopenedDate IS NULL

    UNION ALL

    -- Anomaly 3: Questions with a very high score posted by users with very low reputation
    SELECT p.Id AS PostId, 'LowReputationHighScoreQuestion' AS AnomalyType, p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE u.Reputation < 50 AND p.Score > 20 AND p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '180 days'
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    uas.Reputation,
    uas.TotalPostsCreated,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersPosted,
    uas.AnswersAcceptedByOthers,
    uas.TotalEditsMade,
    COALESCE(uas.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(uas.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(uas.TotalPostScore, 0) AS TotalPostScoreAggregate,
    COALESCE(uas.TotalPostViews, 0) AS TotalPostViewsAggregate,
    rcq.LastClosedDate,
    rcq.LastReopenedDate,
    rcq.CloseReasons,
    pea.EditCount AS LastQuestionEditCount,
    pea.HoursToFirstEdit AS LastQuestionHoursToFirstEdit,
    pea.HoursFromFirstToLastEdit AS LastQuestionHoursFromFirstToLastEdit,
    tp_user.TagName AS UsersTopTagName,
    tp_user.AvgQuestionScoreInTag AS UsersTopTagAvgScore,
    tp_user.AvgQuestionViewsInTag AS UsersTopTagAvgViews,
    -- Correlated subquery to count gold badges
    (SELECT COUNT(ub.BadgeName) FROM UserBadgeSummary ub WHERE ub.UserId = u.Id AND ub.BadgeClass = 1) AS GoldBadgesCount,
    -- Correlated subquery to calculate recent net votes on the user's own posts
    (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE -1 END)
     FROM Votes v JOIN Posts p_v ON v.PostId = p_v.Id
     WHERE p_v.OwnerUserId = u.Id AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days'
    ) AS RecentNetVotesOnOwnPosts,
    -- Count various types of anomalous posts associated with the user
    COALESCE(SUM(CASE WHEN ap.AnomalyType = 'HighEditCountFastEdit' THEN 1 ELSE 0 END), 0) AS HighEditFastAnomalyCount,
    COALESCE(SUM(CASE WHEN ap.AnomalyType = 'MultipleClosedNoReopen' THEN 1 ELSE 0 END), 0) AS MultipleClosedAnomalyCount,
    COALESCE(SUM(CASE WHEN ap.AnomalyType = 'LowReputationHighScoreQuestion' THEN 1 ELSE 0 END), 0) AS LowReputationHighScoreAnomalyCount,
    -- Categorizes user behavior based on various metrics
    CASE
        WHEN uas.TotalQuestionsAsked > 0 AND uas.AnswersAcceptedByOthers > 0
             AND uas.TotalAnswersPosted > 0 AND (uas.AnswersAcceptedByOthers * 1.0 / uas.TotalAnswersPosted) > 0.5
        THEN 'HighAcceptanceRate'
        WHEN uas.TotalEditsMade > COALESCE(uas.TotalPostsCreated, 0) * 3 THEN 'FrequentEditor' -- Anomaly detection: many more edits than posts
        WHEN rcq.ClosureCount > 1 AND rcq.LastReopenedDate IS NULL THEN 'MultipleClosedNoReopen'
        ELSE 'Normal'
    END AS UserBehaviorCategory,
    -- Window function: Ranks users based on their average question score, partitioned by whether they asked questions
    RANK() OVER (PARTITION BY (uas.TotalQuestionsAsked > 0) ORDER BY COALESCE(uas.AvgQuestionScore, -1) DESC NULLS LAST) AS QuestionScoreRank,
    -- Window function: Divides users into 10 groups (deciles) based on their reputation
    NTILE(10) OVER (ORDER BY uas.Reputation DESC) AS ReputationDecile,
    -- String expression: Creates a signature from the display name (first 5 chars lower, last 5 chars upper)
    LOWER(SUBSTRING(u.DisplayName FROM 1 FOR 5)) || '...' || UPPER(SUBSTRING(u.DisplayName FROM LENGTH(u.DisplayName) - 4 FOR 5)) AS DisplayNameSignature,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation, -- NULL logic: Replaces NULL location with 'Unknown Location'
    u.AboutMe LIKE '%SQL%' OR u.AboutMe LIKE '%database%' OR u.AboutMe LIKE '%query%' AS IsAboutSQLOrDB, -- String pattern matching
    NULLIF(u.WebsiteUrl, '') AS UserWebsiteUrlNullIfEmpty, -- NULL logic: Converts empty string website URLs to NULL
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.CreationDate)) AS DaysSinceUserCreation
FROM
    Users u
LEFT JOIN
    UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN
    RecentClosedQuestions rcq ON u.Id = rcq.OwnerUserId AND rcq.PostId = (
        -- Correlated subquery to get the most recent question asked by the user that was recently closed
        SELECT p_q_recent.Id
        FROM Posts p_q_recent
        WHERE p_q_recent.OwnerUserId = u.Id AND p_q_recent.PostTypeId = 1
        ORDER BY p_q_recent.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN
    PostEditMetrics pea ON pea.PostId = rcq.PostId -- Join edit metrics for that specific recent closed question
LEFT JOIN LATERAL ( -- Lateral join to find the 'best performing' tag for a user based on their associated questions
    SELECT
        tp.TagName,
        tp.AvgQuestionScoreInTag,
        tp.AvgQuestionViewsInTag
    FROM TagPerformance tp
    WHERE EXISTS ( -- Checks if the user has asked any question related to this tag
        SELECT 1
        FROM Posts p_tag_user
        WHERE p_tag_user.PostTypeId = 1
          AND p_tag_user.OwnerUserId = u.Id
          AND p_tag_user.Tags IS NOT NULL
          AND (tp.TagName = ANY(string_to_array(substring(p_tag_user.Tags, 2, length(p_tag_user.Tags)-2), '><')))
        LIMIT 1
    )
    ORDER BY tp.AvgQuestionScoreInTag DESC, tp.AvgQuestionViewsInTag DESC -- Order by tag performance to pick the 'best' one
    LIMIT 1
) AS tp_user ON TRUE -- Always attempts to join if a tag exists
LEFT JOIN
    AnomalousPosts ap ON u.Id = ap.OwnerUserId
WHERE
    u.Reputation > 500 -- Filters for users with substantial reputation
    AND u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '365 days' -- Active users within the last year
    AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL) -- NULL logic: Users with some profile information
    AND COALESCE(uas.TotalPostsCreated, 0) > 10 -- Only users with more than 10 posts
GROUP BY -- All non-aggregated columns must be in GROUP BY
    u.Id, u.DisplayName, uas.Reputation, uas.TotalPostsCreated, uas.TotalQuestionsAsked, uas.TotalAnswersPosted,
    uas.AnswersAcceptedByOthers, uas.TotalEditsMade, uas.AvgQuestionScore, uas.AvgAnswerScore, uas.TotalPostScore,
    uas.TotalPostViews, rcq.LastClosedDate, rcq.LastReopenedDate, rcq.CloseReasons, pea.EditCount,
    pea.HoursToFirstEdit, pea.HoursFromFirstToLastEdit, tp_user.TagName, tp_user.AvgQuestionScoreInTag,
    tp_user.AvgQuestionViewsInTag, u.Location, u.AboutMe, u.WebsiteUrl, u.CreationDate, uas.TotalAnswersPosted
HAVING
    COUNT(ap.PostId) < 3 -- Filters out users associated with 3 or more anomalous posts, indicating higher risk or unusual patterns
ORDER BY
    u.Reputation DESC,
    GoldBadgesCount DESC,
    uas.TotalPostsCreated DESC
LIMIT 500;
