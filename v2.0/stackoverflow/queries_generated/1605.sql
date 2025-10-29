-- {"query": "1605.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2866} 

WITH UserProfileSummary AS (
    -- CTE 1: Aggregates user profile data, calculates an influence score, and categorizes users.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown Location') AS UserLocation,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(u.WebsiteUrl) > 10 THEN 'Has Website'
            ELSE 'No Public Website'
        END AS WebsiteStatus,
        SUM(u.UpVotes) AS TotalUserUpVotes,
        SUM(u.DownVotes) AS TotalUserDownVotes,
        COUNT(DISTINCT p_q.Id) AS QuestionsAsked,
        COUNT(DISTINCT p_a.Id) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        MAX(b.Class) FILTER (WHERE b.Class = 1) AS HasGoldBadge,
        (u.Reputation * 0.7 + (u.UpVotes - u.DownVotes) * 0.3) AS CalculatedInfluenceScore, -- Custom influence calculation
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRankOverall
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl
),
PostVersionMetrics AS (
    -- CTE 2: Analyzes post history for edit counts, close/reopen events, and time differences between edits.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteEventCount,
        MAX(ph.CreationDate) AS LatestHistoryDate,
        MIN(ph.CreationDate) AS EarliestHistoryDate,
        ARRAY_AGG(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS DistinctEditorUserIds,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)))) / 3600.0 AS AvgHoursBetweenEdits -- Window function for time diff
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY ph.PostId
),
PotentiallyProblematicPosts AS (
    -- CTE 3: Identifies posts that are "problematic" based on various criteria using UNION ALL.
    SELECT p.Id AS PostId, p.PostTypeId, 'ClosedAndReopened' AS ProblematicType
    FROM Posts p
    JOIN PostVersionMetrics pvm ON p.Id = pvm.PostId
    WHERE p.ClosedDate IS NOT NULL AND pvm.ReopenEventCount > 0
    UNION ALL
    SELECT p.Id AS PostId, p.PostTypeId, 'HighlyEditedButLowScore' AS ProblematicType
    FROM Posts p
    JOIN PostVersionMetrics pvm ON p.Id = pvm.PostId
    WHERE p.PostTypeId = 1 AND pvm.MajorEditCount >= 5 AND p.Score < 0
    UNION ALL
    SELECT p.Id AS PostId, p.PostTypeId, 'ManyDownvotesNoAcceptedAnswer' AS ProblematicType
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL AND p.Score < -5 AND p.AnswerCount > 0
),
SelfAcceptedQuestions AS (
    -- CTE 4: Finds questions where the owner accepted their own answer, then uses EXCEPT to filter out highly downvoted ones.
    SELECT q.Id AS QuestionId
    FROM Posts q
    JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2 AND q.OwnerUserId = a.OwnerUserId
    EXCEPT
    SELECT p.Id AS QuestionId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score <= -10 -- Exclude if highly downvoted
),
QuestionDetailsExtended AS (
    -- CTE 5: Consolidates question-specific details, including correlated subqueries and complex calculations.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastActivityDate,
        q.Tags,
        pvm.MajorEditCount,
        pvm.CloseEventCount,
        pvm.ReopenEventCount,
        pvm.DeleteEventCount,
        COALESCE(pvm.LatestHistoryDate, q.LastActivityDate, q.CreationDate) AS EffectiveLastActivityDate, -- Coalesce for robust date
        (SELECT MAX(ans.Score) FROM Posts ans WHERE ans.ParentId = q.Id AND ans.PostTypeId = 2) AS HighestAnswerScore, -- Correlated subquery
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = q.Id AND c.UserId IS NOT NULL) AS UniqueCommenters,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
         FROM Votes v WHERE v.PostId = q.Id) AS NetVotes,
        EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate)) / (60 * 60 * 24.0) AS DaysSinceCreation, -- Date calculation
        NULLIF(q.AnswerCount, 0) AS NonZeroAnswerCount, -- NULLIF example
        LOWER(SUBSTRING(q.Tags FROM 2 FOR POSITION('><', q.Tags) - 2)) AS PrimaryTag, -- String expression for primary tag
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><') AS TagArray, -- Parse tags into array
        CASE
            WHEN q.FavoriteCount >= 100 AND q.Score > 50 THEN 'Highly Endorsed'
            WHEN q.FavoriteCount >= 20 THEN 'Moderately Popular'
            ELSE 'Standard Engagement'
        END AS EngagementCategory
    FROM Posts q
    LEFT JOIN PostVersionMetrics pvm ON q.Id = pvm.PostId
    WHERE q.PostTypeId = 1 AND q.Title IS NOT NULL AND q.Body IS NOT NULL -- Only valid questions
)
-- Main Query: Joins all CTEs and applies final filtering, window functions, and complex expressions.
SELECT
    qde.QuestionId,
    qde.QuestionTitle,
    qde.QuestionCreationDate,
    ups_owner.DisplayName AS QuestionOwnerDisplayName,
    ups_owner.Reputation AS QuestionOwnerReputation,
    ups_owner.UserLocation AS QuestionOwnerLocation,
    ups_owner.CalculatedInfluenceScore,
    qde.QuestionScore,
    qde.ViewCount,
    qde.AnswerCount,
    qde.FavoriteCount,
    qde.ClosedDate,
    qde.LastActivityDate,
    qde.EffectiveLastActivityDate,
    qde.PrimaryTag,
    qde.MajorEditCount,
    qde.CloseEventCount,
    qde.ReopenEventCount,
    qde.DeleteEventCount,
    qde.HighestAnswerScore,
    qde.UniqueCommenters,
    qde.NetVotes,
    qde.DaysSinceCreation,
    qde.EngagementCategory,
    COALESCE(ppp.ProblematicType, 'Not Problematic') AS ProblematicStatus, -- NULL logic for problematic posts
    CASE WHEN saq.QuestionId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsSelfAccepted,
    STRING_AGG(DISTINCT t.TagName, '; ') AS AllRelatedTags, -- Aggregating all associated tags
    DENSE_RANK() OVER (PARTITION BY qde.PrimaryTag ORDER BY qde.QuestionScore DESC, qde.ViewCount DESC) AS RankInPrimaryTag, -- Window function: rank questions within their primary tag
    AVG(qde.QuestionScore) OVER (PARTITION BY qde.PrimaryTag) AS AvgScoreForPrimaryTag, -- Window function: average score per primary tag
    SUM(qde.ViewCount) OVER (ORDER BY qde.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS Rolling30DayViews, -- Window function: rolling sum
    qde.QuestionScore * 100.0 / NULLIF(qde.ViewCount, 0) AS ScorePerViewRatio, -- Complex calculation
    (SELECT COUNT(DISTINCT badge.Id) FROM Badges badge WHERE badge.UserId = qde.QuestionOwnerId AND badge.Class = 1) AS OwnerGoldBadgeCount, -- Non-correlated subquery
    LOWER(REPLACE(REPLACE(TRIM(qde.QuestionTitle), ' ', '-'), '.', '')) AS CleanedSlugTitle, -- More string manipulation
    (qde.NetVotes + qde.FavoriteCount * 2) AS CalculatedEngagementScore -- Another complex calculation
FROM QuestionDetailsExtended qde
JOIN UserProfileSummary ups_owner ON qde.QuestionOwnerId = ups_owner.UserId
LEFT JOIN PotentiallyProblematicPosts ppp ON qde.QuestionId = ppp.PostId
LEFT JOIN SelfAcceptedQuestions saq ON qde.QuestionId = saq.QuestionId
LEFT JOIN Tags t ON t.TagName = ANY(qde.TagArray) -- Join with Tags table to expand tag information
WHERE qde.ViewCount > 2000 -- Filter for high visibility questions
  AND qde.QuestionScore >= 5 -- Filter for reasonably scored questions
  AND qde.EffectiveLastActivityDate >= (CURRENT_DATE - INTERVAL '2 year') -- Active within last 2 years
  AND qde.PrimaryTag IS NOT NULL AND qde.PrimaryTag <> 'null' -- Ensure a valid primary tag
  AND (qde.AnswerCount > 0 OR qde.ClosedDate IS NOT NULL) -- Must have answers or be closed
  AND ups_owner.Reputation > 500 -- Owner must be somewhat established
  AND ups_owner.UserLocation LIKE '%United States%' -- Example of location-based filter
  AND qde.QuestionTitle ILIKE '%performance%' -- Case-insensitive title search
GROUP BY
    qde.QuestionId, qde.QuestionTitle, qde.CreationDate, ups_owner.DisplayName, ups_owner.Reputation, ups_owner.UserLocation, ups_owner.CalculatedInfluenceScore, qde.QuestionScore, qde.ViewCount, qde.AnswerCount, qde.FavoriteCount, qde.ClosedDate, qde.LastActivityDate, qde.EffectiveLastActivityDate, qde.PrimaryTag, qde.MajorEditCount, qde.CloseEventCount, qde.ReopenEventCount, qde.DeleteEventCount, qde.HighestAnswerScore, qde.UniqueCommenters, qde.NetVotes, qde.DaysSinceCreation, qde.EngagementCategory, ppp.ProblematicType, saq.QuestionId
ORDER BY
    CalculatedEngagementScore DESC, qde.EffectiveLastActivityDate DESC
LIMIT 200;
