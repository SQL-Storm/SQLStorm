-- {"query": "1974.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2460} 

WITH UserActivityMetrics AS (
    -- CTE 1: Summarize user activity, reputation tiers, and badge status
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile, -- Window function: NTILE for reputation bucketing
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgOverallPostScore, -- Aggregate with FILTER clause
        COALESCE(u.Location, 'Unknown Location') AS UserLocation, -- NULL logic: COALESCE for display
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)::boolean AS HasGoldBadge -- Check for gold badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.Location
),
PostTagAnalysis AS (
    -- CTE 2: Extract and analyze tags for questions, focusing on "performance" or "benchmark"
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.AcceptedAnswerId,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.Tags,
        p.FavoriteCount,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS TagCount, -- String functions: SUBSTRING, LENGTH, STRING_TO_ARRAY, ARRAY_LENGTH
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        (LOWER(p.Title) LIKE '%performance%' OR LOWER(p.Body) LIKE '%benchmark%') AS IsPerformanceBenchmarkPost -- Complicated predicate: OR condition on string matching
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.Tags IS NOT NULL
      AND p.Title IS NOT NULL
      AND p.Score >= 0
),
LatestPostEdit AS (
    -- CTE 3: Get the latest edit information for each post (title, body, tags)
    SELECT
        ph.PostId,
        ph.CreationDate AS LastEditDate,
        ph.UserId AS LastEditorUserId,
        ph.UserDisplayName AS LastEditorDisplayName,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn -- Window function: ROW_NUMBER to get the latest edit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostCloseReasonDetails AS (
    -- CTE 4: Identify close reasons for closed posts from PostHistory
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_close -- Window function: ROW_NUMBER for the most recent close reason
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id -- Complicated expression: CAST for join condition
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
HighScoringUserContent AS (
    -- CTE 5: Identify high-scoring posts and comments by users using a set operator
    SELECT UserId, PostId AS ContentId, 'Post' AS ContentType, Score
    FROM Posts WHERE Score > 20 AND OwnerUserId IS NOT NULL
    UNION ALL -- Set operator: UNION ALL to combine posts and comments
    SELECT UserId, Id AS ContentId, 'Comment' AS ContentType, Score
    FROM Comments WHERE Score > 10 AND UserId IS NOT NULL
)
-- Main Query: Combine information to analyze performance-related questions
SELECT
    pta.PostId,
    pta.Title,
    pta.Score AS QuestionScore,
    pta.ViewCount AS QuestionViewCount,
    pta.CreationDate AS QuestionCreationDate,
    uam.DisplayName AS QuestionOwnerDisplayName,
    uam.Reputation AS QuestionOwnerReputation,
    uam.ReputationQuartile,
    uam.HasGoldBadge,
    lpe.LastEditDate AS QuestionLastEditDate,
    COALESCE(lpe.LastEditorDisplayName, 'No Editor') AS LastEditorName, -- NULL logic: COALESCE for display
    pcr.CloseReasonName,
    pta.TagCount,
    pta.IsPerformanceBenchmarkPost,
    CASE -- Complicated predicate/NULL logic: CASE statement for post status
        WHEN pta.ClosedDate IS NOT NULL AND pcr.CloseReasonName IS NULL THEN 'Closed (Reason Unknown)'
        WHEN pta.ClosedDate IS NOT NULL THEN 'Closed (' || pcr.CloseReasonName || ')' -- String concatenation
        ELSE 'Open'
    END AS PostStatusDetail,
    AVG(CASE WHEN ans.Score > 0 THEN ans.Score END) OVER (PARTITION BY pta.PostId) AS AvgPositiveAnswerScore, -- Window function with conditional aggregation
    COUNT(DISTINCT ans.Id) AS TotalAnswersReceived,
    SUM(CASE WHEN ans.AcceptedAnswerId = pta.PostId THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
    SUM(CASE WHEN ans.CreationDate > pta.CreationDate + INTERVAL '1 month' THEN 1 ELSE 0 END) AS LateAnswersCount, -- Date arithmetic
    -- Correlated Subquery 1: Get the maximum comment score for the current question
    (
        SELECT COALESCE(MAX(c.Score), 0)
        FROM Comments c
        WHERE c.PostId = pta.PostId
    ) AS MaxQuestionCommentScore,
    -- Correlated Subquery 2: Check if any post history for this question was by a moderator (hardcoded Type 15 for ModeratorReview)
    (
        SELECT EXISTS (
            SELECT 1 FROM PostHistory ph WHERE ph.PostId = pta.PostId AND ph.PostHistoryTypeId = 15
        )
    ) AS HadModeratorReview,
    NULLIF(EXTRACT(EPOCH FROM (lpe.LastEditDate - pta.CreationDate)) / 3600, 0) AS HoursToFirstEdit, -- Date calculation, NULLIF for division by zero
    COUNT(hsc.ContentId) FILTER (WHERE hsc.ContentType = 'Post') AS OwnerHighScorePosts, -- Aggregate with FILTER
    COUNT(hsc.ContentId) FILTER (WHERE hsc.ContentType = 'Comment') AS OwnerHighScoreComments, -- Aggregate with FILTER
    RANK() OVER (PARTITION BY uam.ReputationQuartile ORDER BY pta.Score DESC, pta.ViewCount DESC) AS RankWithinReputationQuartile, -- Window function: RANK
    LAG(pta.Score, 1, 0) OVER (PARTITION BY uam.UserId ORDER BY pta.CreationDate) AS PreviousPostScoreByOwner, -- Window function: LAG
    COALESCE(plt.Name, 'No Link') AS RelatedPostLinkType, -- NULL logic: COALESCE
    CASE WHEN plt.Id = 3 THEN 'Duplicate' ELSE 'Not Duplicate' END AS IsDuplicateLink, -- NULL logic: CASE for link type
    (
        SELECT COUNT(DISTINCT tags.TagName)
        FROM UNNEST(pta.TagArray) AS tags(TagName)
        WHERE tags.TagName LIKE 'sql%' OR tags.TagName LIKE 'database%'
    ) AS DatabaseRelatedTagsCount -- Correlated subquery with UNNEST and string matching
FROM PostTagAnalysis pta
JOIN UserActivityMetrics uam ON pta.OwnerUserId = uam.UserId
LEFT JOIN LatestPostEdit lpe ON pta.PostId = lpe.PostId AND lpe.rn = 1 -- Outer join for latest edit
LEFT JOIN PostCloseReasonDetails pcr ON pta.PostId = pcr.PostId AND pcr.rn_close = 1 -- Outer join for close reason
LEFT JOIN Posts ans ON pta.Id = ans.ParentId AND ans.PostTypeId = 2 -- Outer join for answers to this question
LEFT JOIN PostLinks pl ON pta.PostId = pl.PostId -- Outer join for post links
LEFT JOIN LinkTypes plt ON pl.LinkTypeId = plt.Id
LEFT JOIN HighScoringUserContent hsc ON uam.UserId = hsc.UserId
WHERE uam.Reputation > 500 -- Minimum reputation for owners
  AND pta.CreationDate >= '2021-01-01' -- Recent posts analysis
  AND pta.IsPerformanceBenchmarkPost IS TRUE -- Focus on specific posts
  AND EXISTS ( -- Correlated subquery in WHERE: ensures posts have at least one comment within 2 days
      SELECT 1 FROM Comments c_exist WHERE c_exist.PostId = pta.PostId AND c_exist.CreationDate BETWEEN pta.CreationDate AND pta.CreationDate + INTERVAL '2 day'
  )
  AND uam.UserLocation IS NOT NULL -- Example of IS NOT NULL predicate
GROUP BY
    pta.PostId, pta.Title, pta.Score, pta.ViewCount, pta.CreationDate, uam.DisplayName, uam.Reputation,
    uam.ReputationQuartile, uam.HasGoldBadge, lpe.LastEditDate, lpe.LastEditorDisplayName, pcr.CloseReasonName,
    pta.TagCount, pta.IsPerformanceBenchmarkPost, pta.ClosedDate, uam.UserId, plt.Name, plt.Id, pta.TagArray
ORDER BY
    uam.Reputation DESC, pta.Score DESC, pta.CreationDate DESC
LIMIT 500;
