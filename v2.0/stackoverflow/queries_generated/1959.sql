-- {"query": "1959.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2129} 

WITH UserInfluence AS (
    -- Identify influential users based on reputation rank and gold badges count.
    -- Includes a window function (RANK) and aggregation.
    SELECT
        u.Id AS UserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        u.WebsiteUrl,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgesCount,
        RANK() OVER (ORDER BY u.Reputation DESC, COUNT(CASE WHEN b.Class = 1 THEN 1 END) DESC) AS ReputationRank
    FROM
        Users AS u
    LEFT JOIN
        Badges AS b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.WebsiteUrl
    HAVING
        u.Reputation >= 10000 AND COUNT(CASE WHEN b.Class = 1 THEN 1 END) >= 5
),
QuestionActivitySummary AS (
    -- Summarize key activities for questions, including aggregate comment scores
    -- and a correlated subquery for the latest comment date by a non-owner.
    SELECT
        p.Id AS PostId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Tags,
        p.Score AS QuestionScore,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        (SELECT MAX(c_corr.CreationDate)
         FROM Comments AS c_corr
         WHERE c_corr.PostId = p.Id AND c_corr.UserId IS NOT NULL AND c_corr.UserId != p.OwnerUserId
        ) AS LatestNonOwnerCommentDate, -- Correlated subquery
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM
        Posts AS p
    LEFT JOIN
        Comments AS c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1 -- Only Questions
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.OwnerUserId, p.AcceptedAnswerId, p.Tags, p.Score
    HAVING
        p.ViewCount > 5000 -- Filter for reasonably viewed questions
),
PostEditAnalysis AS (
    -- Analyze edit history for posts, calculating number of edits, distinct editors,
    -- and average time between consecutive edits using a LATERAL join to simulate LAG.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS NumberOfEdits,
        COUNT(DISTINCT ph.UserId) AS NumberOfDistinctEditors,
        MAX(ph.CreationDate) AS LastEditDate,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - prev_ph.CreationDate))) FILTER (WHERE prev_ph.CreationDate IS NOT NULL) AS AvgEditIntervalSeconds
    FROM
        PostHistory AS ph
    LEFT JOIN LATERAL ( -- Emulates LAG functionality for previous edit date
        SELECT ph_inner.CreationDate
        FROM PostHistory AS ph_inner
        WHERE ph_inner.PostId = ph.PostId
          AND ph_inner.CreationDate < ph.CreationDate
          AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
        ORDER BY ph_inner.CreationDate DESC
        LIMIT 1
    ) AS prev_ph ON TRUE
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY
        ph.PostId
    HAVING
        COUNT(ph.Id) >= 3 -- At least 3 edits
),
AnswerVoteControversy AS (
    -- Calculate a controversy ratio for answers associated with each question.
    -- This reflects the downvote-to-upvote ratio across all answers for a question.
    SELECT
        p_ans.ParentId AS QuestionId,
        CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS ControversyRatio
    FROM
        Posts AS p_ans
    INNER JOIN
        Votes AS v ON p_ans.Id = v.PostId
    WHERE
        p_ans.PostTypeId = 2 -- Only Answers
    GROUP BY
        p_ans.ParentId
    HAVING
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0 -- Must have at least one upvote to be considered
),
QuestionClosureStatus AS (
    -- Determine if a question was ever closed and/or reopened, and count such events.
    SELECT
        ph_close.PostId,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN ph_close.PostHistoryTypeId = 11 THEN 'Reopened'
                 ELSE 'Unknown' END) AS FinalClosureState,
        COUNT(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
        COUNT(CASE WHEN ph_close.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount
    FROM
        PostHistory AS ph_close
    WHERE
        ph_close.PostHistoryTypeId IN (10, 11) -- Post Closed or Post Reopened
    GROUP BY
        ph_close.PostId
)
SELECT
    qas.PostId,
    qas.QuestionTitle,
    ui.OwnerDisplayName,
    ui.Reputation,
    ui.GoldBadgesCount,
    pa.NumberOfEdits,
    pa.NumberOfDistinctEditors,
    COALESCE(pa.AvgEditIntervalSeconds, 0) AS AvgEditIntervalSeconds, -- NULL logic for average interval
    COALESCE(avc.ControversyRatio, 0.0) AS AnswerControversyRatio, -- NULL logic for controversy
    CASE
        WHEN EXISTS ( -- Correlated subquery to check for duplicate links
            SELECT 1
            FROM PostLinks AS pl_dup
            WHERE pl_dup.PostId = qas.PostId
              AND pl_dup.LinkTypeId = 3 -- Duplicate link type
        ) THEN 'Yes'
        ELSE 'No'
    END AS HasDuplicateLink,
    (qas.QuestionScore + qas.TotalCommentScore) AS CombinedActivityScore, -- Complex calculation
    EXTRACT(DAY FROM AGE(NOW(), qas.QuestionCreationDate)) AS DaysSinceCreation, -- Date arithmetic
    CASE -- Complex conditional expression for discussion level
        WHEN qas.LatestNonOwnerCommentDate IS NOT NULL AND qas.CommentCount > 5 AND COALESCE(avc.ControversyRatio, 0.0) > 0.5 THEN 'Highly Discussed & Potentially Controversial'
        WHEN qas.LatestNonOwnerCommentDate IS NOT NULL AND qas.CommentCount > 2 THEN 'Moderately Discussed'
        ELSE 'Low Discussion'
    END AS DiscussionLevel,
    COALESCE(qcs.FinalClosureState, 'Never Closed') AS ClosureState, -- NULL logic
    qcs.CloseCount,
    qcs.ReopenCount,
    -- Example of complex string expressions with NULL logic for tags
    COALESCE(LOWER(SPLIT_PART(SUBSTRING(qas.Tags FROM 2 FOR LENGTH(qas.Tags) - 2), '><', 1)), 'no_tag') AS FirstTagLowerCase,
    LENGTH(qas.Tags) - LENGTH(REPLACE(qas.Tags, '><', '')) + 1 AS NumberOfTags -- Count tags by delimiter
FROM
    QuestionActivitySummary AS qas
INNER JOIN
    UserInfluence AS ui ON qas.OwnerUserId = ui.UserId
LEFT JOIN
    PostEditAnalysis AS pa ON qas.PostId = pa.PostId
LEFT JOIN
    AnswerVoteControversy AS avc ON qas.PostId = avc.QuestionId
LEFT JOIN
    QuestionClosureStatus AS qcs ON qas.PostId = qcs.PostId
WHERE
    qas.AcceptedAnswerId IS NOT NULL -- Question must have an accepted answer
    AND ui.WebsiteUrl IS NOT NULL -- Influential user must have a website URL
    AND (qas.Tags ILIKE '%<sql>%' OR qas.Tags ILIKE '%<database>%') -- Must contain 'sql' or 'database' tag (case-insensitive)
    AND qas.Tags NOT ILIKE '%<deprecated-feature>%' -- Exclude questions about deprecated features
    AND pa.PostId IS NOT NULL -- Only include questions that meet the edit analysis criteria (at least 3 edits)
    AND qas.LatestNonOwnerCommentDate > NOW() - INTERVAL '1 year' -- Last non-owner comment within the last year
    AND ui.ReputationRank <= 1000 -- Only top 1000 influential users by reputation and badge count
    AND (LENGTH(qas.QuestionTitle) BETWEEN 30 AND 150) -- Title length constraint
ORDER BY
    avc.ControversyRatio DESC NULLS LAST, -- NULL logic for sorting
    CombinedActivityScore DESC,
    pa.NumberOfDistinctEditors DESC
LIMIT 1000;
