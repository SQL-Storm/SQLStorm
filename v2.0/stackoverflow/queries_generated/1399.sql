-- {"query": "1399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3935} 

WITH UserEngagementStats AS (
    -- CTE 1: Aggregates user activity, including various post, comment, and vote counts,
    -- along with calculated age of account and days since last access.
    -- Demonstrates: Outer joins, complicated predicates, `COALESCE`, `EXTRACT`, `HAVING` clause, conditional aggregation.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60*60*24) AS AccountAgeDays,
        EXTRACT(EPOCH FROM (NOW() - u.LastAccessDate)) / (60*60*24) AS DaysSinceLastAccess,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0) AS AvgPostScore,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesCast,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesCast
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    WHERE u.Reputation > 100
      AND u.DisplayName IS NOT NULL
      AND u.WebsiteUrl IS NOT NULL
      AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50 -- String expression and predicate
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT c.Id) > 10 -- Complicated predicate
),
PostInteractionMetrics AS (
    -- CTE 2: Focuses on Question posts, calculating various engagement metrics,
    -- including accepted answer details, edit counts, and close vote counts.
    -- Demonstrates: Correlated subqueries, `CASE WHEN`, `NULL` logic, `STRING_TO_ARRAY`, `SUBSTRING`, `LENGTH`.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount,
        q.ClosedDate,
        COALESCE(q.Tags, '') AS QuestionTags,
        COALESCE(q.LastEditDate, q.CreationDate) AS LastEditOrCreationDate,
        EXTRACT(EPOCH FROM (COALESCE(q.LastActivityDate, q.CreationDate) - q.CreationDate)) / (60*60*24) AS DaysActive,
        COALESCE(qa.Score, 0) AS AcceptedAnswerScore,
        COALESCE(qa.OwnerUserId, -1) AS AcceptedAnswerOwnerUserId,
        (SELECT COUNT(DISTINCT ph_edit.UserId) -- Correlated subquery for distinct editors
         FROM PostHistory AS ph_edit
         WHERE ph_edit.PostId = q.Id
           AND ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS DistinctEditorCount,
        (SELECT COUNT(ph_close.Id)
         FROM PostHistory AS ph_close
         WHERE ph_close.PostId = q.Id
           AND ph_close.PostHistoryTypeId = 10
           AND ph_close.Comment IS NOT NULL) AS CloseVoteCommentCount, -- Predicate on PostHistory comment
        CASE -- `NULL` logic with conditional expression
            WHEN q.AcceptedAnswerId IS NOT NULL AND q.OwnerUserId = (SELECT a.OwnerUserId FROM Posts a WHERE a.Id = q.AcceptedAnswerId) THEN TRUE
            WHEN q.AcceptedAnswerId IS NOT NULL AND q.OwnerUserId != (SELECT a.OwnerUserId FROM Posts a WHERE a.Id = q.AcceptedAnswerId) THEN FALSE
            ELSE NULL
        END AS AcceptedAnswerBySelf,
        COALESCE( -- Calculation with `NULL` logic
            EXTRACT(EPOCH FROM (qa.CreationDate - q.CreationDate)) / (60*60),
            -1.0
        ) AS AcceptedAnswerHoursDelay,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><') AS ParsedTags -- String expressions
    FROM Posts AS q
    LEFT JOIN Posts AS qa ON q.AcceptedAnswerId = qa.Id AND qa.PostTypeId = 2 -- Outer join
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= '2020-01-01'
      AND q.ViewCount > 50
      AND q.CommentCount > 0
      AND (q.Score > 5 OR q.FavoriteCount > 0)
),
PostEditTimings AS (
    -- CTE 3: Analyzes edit history for posts to calculate time between edits.
    -- Demonstrates: Window functions (`LAG`), `EXTRACT` for time difference.
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate, -- Window function
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / (60*60) AS HoursSincePreviousEdit, -- Calculation with window function
        ph.UserId AS EditorUserId
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Body, Tags, or Rollback Body
      AND ph.UserId IS NOT NULL
      AND ph.CreationDate >= '2020-01-01'
),
PostEditSummary AS (
    -- CTE 4: Summarizes edit activity per post based on PostEditTimings.
    -- Demonstrates: Conditional aggregation (`FILTER`), `NULLIF` for division by zero.
    SELECT
        PostId,
        COUNT(DISTINCT EditorUserId) AS UniqueEditors,
        MAX(HoursSincePreviousEdit) AS MaxHoursBetweenEdits,
        AVG(HoursSincePreviousEdit) FILTER (WHERE HoursSincePreviousEdit > 0) AS AvgHoursBetweenEdits,
        COUNT(EditDate) AS TotalEdits,
        COUNT(DISTINCT EditorUserId) * 1.0 / NULLIF(COUNT(EditDate), 0) AS EditorDiversityRatio -- Calculation with `NULLIF`
    FROM PostEditTimings
    GROUP BY PostId
),
AnswerQualityMetrics AS (
    -- CTE 5: Focuses on Answer posts, calculating their score relative to parent questions,
    -- comment counts, accepted vote counts, and late upvotes.
    -- Demonstrates: `COALESCE`, `NULLIF`, `LENGTH`, `COUNT` with `CASE WHEN`, another correlated subquery.
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionParentId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        COALESCE(a.Body, '') AS AnswerBody, -- `NULL` logic for string
        COUNT(DISTINCT c.Id) AS AnswerCommentCount,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVoteCount, -- Specific vote type aggregation
        q.Score AS ParentQuestionScore,
        q.ViewCount AS ParentQuestionViewCount,
        (a.Score * 1.0 / NULLIF(q.Score, 0)) AS ScoreRatioToQuestion, -- Calculation with `NULLIF`
        (SELECT COUNT(DISTINCT pha.UserId) -- Correlated subquery for distinct editors of an answer
         FROM PostHistory pha
         WHERE pha.PostId = a.Id AND pha.PostHistoryTypeId IN (4,5,6)) AS AnswerDistinctEditorCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 AND v.CreationDate > a.CreationDate + INTERVAL '1 month' THEN v.Id END) AS LateUpvotes -- Complex predicate for vote timing
    FROM Posts AS a
    LEFT JOIN Posts AS q ON a.ParentId = q.Id
    LEFT JOIN Comments AS c ON a.Id = c.PostId
    LEFT JOIN Votes AS v ON a.Id = v.PostId
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= '2020-01-01'
      AND a.Score > 0
      AND a.ParentId IS NOT NULL
      AND LENGTH(a.Body) > 100 -- String predicate
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score, a.Body, q.Score, q.ViewCount
)
-- Main query: Combines results from the CTEs and applies final calculations, ranking, and filtering.
-- Demonstrates: Set operator (`UNION ALL`), `RANK()`, `NTILE()`, `LAG()`, `COALESCE`, `NULLIF`,
-- `EXISTS` with `UNNEST`, string functions (`UPPER`, `LEFT`, `LPAD`), and non-correlated subqueries.
SELECT
    'Question' AS PostCategory,
    pim.QuestionId AS PostId,
    pim.QuestionTitle AS PostTitle,
    ues.DisplayName AS PostOwnerDisplayName,
    ues.Reputation AS PostOwnerReputation,
    pim.QuestionCreationDate AS PostCreationDate,
    pim.QuestionScore AS PostScore,
    pim.ViewCount,
    pim.AnswerCount,
    pim.QuestionCommentCount AS CommentCount,
    pim.FavoriteCount,
    pim.AcceptedAnswerScore,
    pim.AcceptedAnswerBySelf,
    pim.AcceptedAnswerHoursDelay,
    COALESCE(pes.TotalEdits, 0) AS PostEditCount,
    COALESCE(pes.UniqueEditors, 0) AS PostUniqueEditors,
    pes.AvgHoursBetweenEdits,
    pim.CloseVoteCommentCount AS CloseVoteCount,
    (SELECT COUNT(DISTINCT TagName) FROM UNNEST(pim.ParsedTags) AS TagName WHERE TagName LIKE '%database%' OR TagName LIKE '%nosql%') AS TagMatchCount, -- String array expression
    RANK() OVER (ORDER BY pim.QuestionScore DESC, pim.ViewCount DESC, pim.AnswerCount DESC, pim.FavoriteCount DESC) AS RankByEngagementImpact, -- Window function for ranking
    NTILE(10) OVER (ORDER BY pim.QuestionCreationDate) AS CreationDateDecile, -- Window function for deciles
    LAG(pim.QuestionScore, 1, 0) OVER (ORDER BY pim.QuestionCreationDate) AS PreviousPostScore, -- Window function with `NULL` logic
    (pim.QuestionScore * 1.0 / NULLIF(ues.TotalQuestionsOwned, 0)) AS AvgScorePerOwnedPostRatio, -- Calculation with `NULLIF`
    COALESCE(ues.Location, 'Unspecified') AS OwnerLocation, -- `NULL` logic for location
    UPPER(LEFT(COALESCE(ues.Location, 'U'), 3)) || '-' || LPAD(pim.QuestionId::TEXT, 8, '0') AS UniquePostIdentifier, -- Complex string calculation
    COALESCE(pes.EditorDiversityRatio, 0.0) AS EditorDiversityRatio,
    (SELECT COALESCE(SUM(v.BountyAmount), 0) FROM Votes v WHERE v.PostId = pim.QuestionId AND v.VoteTypeId = 8) AS TotalBountyAmount -- Non-correlated subquery
FROM PostInteractionMetrics AS pim
LEFT JOIN UserEngagementStats AS ues ON pim.QuestionOwnerUserId = ues.UserId
LEFT JOIN PostEditSummary AS pes ON pim.QuestionId = pes.PostId
WHERE pim.QuestionOwnerUserId IS NOT NULL
  AND pim.QuestionScore > 10
  AND pim.ViewCount > 500
  AND (EXISTS (SELECT 1 FROM UNNEST(pim.ParsedTags) AS TagName WHERE TagName = 'performance' OR TagName = 'optimization') OR pim.QuestionTitle LIKE '%benchmark%') -- Complicated predicate (string/array)
  AND pim.QuestionId NOT IN (SELECT RelatedPostId FROM PostLinks WHERE LinkTypeId = 3 AND CreationDate >= '2021-01-01') -- Non-correlated subquery as filter
  AND (pim.AcceptedAnswerBySelf IS FALSE OR pim.AcceptedAnswerBySelf IS NULL) -- `NULL` logic in predicate

UNION ALL

SELECT
    'Answer' AS PostCategory,
    aqm.AnswerId AS PostId,
    LEFT(aqm.AnswerBody, 100) AS PostTitle, -- String expression for snippet
    ues.DisplayName AS PostOwnerDisplayName,
    ues.Reputation AS PostOwnerReputation,
    aqm.AnswerCreationDate AS PostCreationDate,
    aqm.AnswerScore AS PostScore,
    aqm.ParentQuestionViewCount AS ViewCount,
    NULL AS AnswerCount, -- Not applicable for answers
    aqm.AnswerCommentCount AS CommentCount,
    NULL AS FavoriteCount, -- Not applicable
    NULL AS AcceptedAnswerScore, -- Not applicable
    NULL AS AcceptedAnswerBySelf, -- Not applicable
    NULL AS AcceptedAnswerHoursDelay, -- Not applicable
    COALESCE(pes.TotalEdits, 0) AS PostEditCount,
    COALESCE(pes.UniqueEditors, 0) AS PostUniqueEditors,
    pes.AvgHoursBetweenEdits,
    NULL AS CloseVoteCount, -- Not applicable for answers
    (SELECT COUNT(DISTINCT TagName) FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS TagName WHERE TagName LIKE '%algorithm%' OR TagName LIKE '%data-structure%') AS TagMatchCount, -- String array expression
    RANK() OVER (ORDER BY aqm.AnswerScore DESC, aqm.AcceptedVoteCount DESC, aqm.AnswerCommentCount DESC) AS RankByEngagementImpact, -- Window function
    NTILE(10) OVER (ORDER BY aqm.AnswerCreationDate) AS CreationDateDecile, -- Window function
    LAG(aqm.AnswerScore, 1, 0) OVER (ORDER BY aqm.AnswerCreationDate) AS PreviousPostScore, -- Window function with `NULL` logic
    (aqm.AnswerScore * 1.0 / NULLIF(ues.TotalAnswersOwned, 0)) AS AvgScorePerOwnedPostRatio, -- Calculation with `NULLIF`
    COALESCE(ues.Location, 'Unspecified') AS OwnerLocation,
    UPPER(LEFT(COALESCE(ues.Location, 'U'), 3)) || '-' || LPAD(aqm.AnswerId::TEXT, 8, '0') AS UniquePostIdentifier, -- Complex string calculation
    COALESCE(pes.EditorDiversityRatio, 0.0) AS EditorDiversityRatio,
    aqm.LateUpvotes AS TotalBountyAmount -- Reusing column name for a different, but type-compatible, metric for answers
FROM AnswerQualityMetrics AS aqm
LEFT JOIN Posts AS q ON aqm.QuestionParentId = q.Id -- Join to get parent question tags for filtering
LEFT JOIN UserEngagementStats AS ues ON aqm.AnswerOwnerUserId = ues.UserId
LEFT JOIN PostEditSummary AS pes ON aqm.AnswerId = pes.PostId
WHERE aqm.AnswerOwnerUserId IS NOT NULL
  AND aqm.AnswerScore > 5
  AND aqm.AcceptedVoteCount > 0
  AND aqm.ScoreRatioToQuestion IS NOT NULL
  AND LENGTH(aqm.AnswerBody) > 200
  AND (aqm.AnswerId IN (SELECT PostId FROM Comments WHERE Score > 0 GROUP BY PostId HAVING COUNT(Id) > 1)) -- Non-correlated subquery as filter
  AND q.Tags IS NOT NULL AND q.Tags LIKE '%<programming>%' -- Predicate on parent question tags
ORDER BY PostCreationDate DESC, RankByEngagementImpact ASC;
