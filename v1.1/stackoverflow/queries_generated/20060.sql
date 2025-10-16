-- {"query": "20060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1635} 

WITH UserEngagement AS (
    -- Calculate various engagement metrics for each user to identify power users.
    -- This includes counts of different post types, comments, votes, and badges.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT q.Id) AS QuestionsPosted,
        COUNT(DISTINCT a.Id) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsWritten,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgesEarned,
        AVG(a.Score) FILTER (WHERE a.Id IS NOT NULL) AS AverageAnswerScore,
        (u.Reputation * 0.4 + COALESCE(COUNT(DISTINCT a.Id), 0) * 0.3 + (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) * 0.2 + (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) * 0.1) AS EngagementScore
    FROM Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1 -- Questions
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '2 year') AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT a.Id) > 10
),
RankedUsers AS (
    -- Use window functions to rank users and partition them by location.
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY EngagementScore DESC, Reputation DESC) AS OverallRank,
        NTILE(100) OVER (ORDER BY EngagementScore DESC) AS EngagementPercentile,
        AVG(EngagementScore) OVER (PARTITION BY SUBSTRING(Location, POSITION(',' IN Location) + 1)) AS AvgScoreForLocation
    FROM UserEngagement
),
QuestionDetails AS (
    -- For questions asked by top-ranked users, gather detailed metrics,
    -- including time-to-answer and edit history.
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.Tags,
        p.CreationDate AS QuestionCreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        -- Correlated subquery to find the time of the first answer
        (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = p.Id) AS FirstAnswerDate,
        -- Use LEAD window function on post history to find time between edits
        (
            SELECT EXTRACT(EPOCH FROM (MIN(ph_next.CreationDate) - ph.CreationDate))
            FROM PostHistory ph
            LEFT JOIN PostHistory ph_next ON ph_next.PostId = ph.PostId AND ph_next.CreationDate > ph.CreationDate
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6) -- Body, Title, or Tag edits
            GROUP BY ph.CreationDate
            ORDER BY ph.CreationDate
            LIMIT 1
        ) AS AvgSecondsBetweenEdits
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
    AND p.OwnerUserId IN (SELECT UserId FROM RankedUsers WHERE EngagementPercentile <= 5) -- Questions from top 5% users
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate > '2019-01-01')
)
-- Main query to combine user rankings and question details, plus a union with a different user cohort.
(
SELECT
    ru.DisplayName,
    ru.Reputation,
    ru.OverallRank,
    ru.EngagementScore,
    qd.Title AS QuestionTitle,
    qd.Score AS QuestionScore,
    qd.ViewCount,
    -- Calculate time differences and other metrics
    EXTRACT(EPOCH FROM (qd.FirstAnswerDate - qd.QuestionCreationDate)) / 3600.0 AS HoursToFirstAnswer,
    CASE
        WHEN qd.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN qd.AnswerCount = 0 THEN 'Unanswered'
        ELSE 'Answered'
    END AS QuestionStatus,
    -- Complex string manipulation on tags
    UPPER(REPLACE(SUBSTRING(qd.Tags FROM 2 FOR LENGTH(qd.Tags) - 2), '><', ' | ')) AS FormattedTags,
    (qd.Score + qd.FavoriteCount * 5.0) / GREATEST(qd.ViewCount, 1) * 1000 AS PopularityMetric,
    -- Fetch the type of the last edit on the post
    (
        SELECT pht.Name
        FROM PostHistory ph
        JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE ph.PostId = qd.QuestionId
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    ) AS LastEditType
FROM RankedUsers ru
JOIN QuestionDetails qd ON ru.UserId = qd.OwnerUserId
WHERE
    qd.FirstAnswerDate IS NOT NULL
    AND qd.AnswerCount > 0
    AND (ru.Location LIKE '%California%' OR ru.AvgScoreForLocation > ru.EngagementScore)
)
UNION ALL
(
-- Combine with a different set of users: those with many downvoted answers.
SELECT
    u.DisplayName,
    u.Reputation,
    NULL AS OverallRank,
    NULL AS EngagementScore,
    p_q.Title AS QuestionTitle,
    p_a.Score AS AnswerScore,
    p_q.ViewCount,
    NULL AS HoursToFirstAnswer,
    'Low-Score Answer Provider' AS QuestionStatus,
    p_q.Tags AS FormattedTags,
    NULL AS PopularityMetric,
    NULL AS LastEditType
FROM Users u
JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 -- Answers
JOIN Posts p_q ON p_a.ParentId = p_q.Id -- The question for the answer
WHERE u.Id IN (
    -- Select users who have at least 5 answers with a negative score
    SELECT OwnerUserId
    FROM Posts
    WHERE PostTypeId = 2 AND Score < 0 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    HAVING COUNT(*) >= 5
)
AND p_a.Score < -1
AND u.DownVotes > u.UpVotes
)
ORDER BY Reputation DESC, QuestionScore DESC NULLS LAST, HoursToFirstAnswer ASC
LIMIT 1000;
