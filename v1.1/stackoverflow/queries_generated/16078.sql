-- {"query": "16078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1975}

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PrevUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2
    WHERE u.Reputation > 100
        AND u.CreationDate >= TIMESTAMP '2015-01-01'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwnerId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionDate,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 1 
            ELSE 0 
        END AS IsAccepted,
        CASE
            WHEN a.CreationDate <= q.CreationDate + INTERVAL '1 hour' THEN 'Fast'
            WHEN a.CreationDate <= q.CreationDate + INTERVAL '1 day' THEN 'Medium'
            ELSE 'Slow'
        END AS ResponseSpeed,
        STRING_AGG(DISTINCT t.TagName, ',') OVER (PARTITION BY q.Id) AS QuestionTags,
        AVG(a.Score) OVER (PARTITION BY q.Id) AS AvgAnswerScore,
        MAX(a.Score) OVER (PARTITION BY q.Id) AS MaxAnswerScore
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    LEFT JOIN LATERAL (
        SELECT TagName 
        FROM Tags 
        WHERE '<' || TagName || '>' = ANY(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><'))
        LIMIT 3
    ) t ON TRUE
    WHERE q.PostTypeId = 1
        AND a.PostTypeId = 2
        AND q.ClosedDate IS NULL
        AND q.CreationDate >= TIMESTAMP '2018-01-01'
        AND (q.ViewCount > 100 OR q.Score > 5)
),
VotePatterns AS (
    SELECT 
        v.PostId,
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount,
        MAX(v.CreationDate) AS LastVoteDate,
        EXTRACT(EPOCH FROM (MAX(v.CreationDate) - MIN(v.CreationDate))) / 3600.0 AS VoteSpreadHours
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
        AND v.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY v.PostId, v.UserId
)
SELECT 
    uam.DisplayName,
    uam.Location,
    uam.Reputation,
    uam.ReputationRank,
    uam.PostCount,
    uam.BadgeCount,
    ROUND(AVG(qas.QuestionScore)::numeric, 2) AS AvgQuestionScore,
    ROUND(AVG(qas.ViewCount)::numeric, 2) AS AvgViewCount,
    COUNT(DISTINCT qas.QuestionId) AS QuestionsAsked,
    COUNT(DISTINCT qas.AnswerId) AS AnswersGiven,
    SUM(qas.IsAccepted) AS AcceptedAnswers,
    ROUND(100.0 * SUM(qas.IsAccepted) / NULLIF(COUNT(DISTINCT qas.AnswerId), 0), 2) AS AcceptanceRate,
    COALESCE(STRING_AGG(DISTINCT SUBSTRING(qas.Title, 1, 30), ' | '), 'N/A') AS SampleTitles,
    (
        SELECT COUNT(DISTINCT ph.Id)
        FROM PostHistory ph
        WHERE ph.UserId = uam.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.CreationDate >= TIMESTAMP '2020-01-01'
    ) AS EditCount,
    (
        SELECT COALESCE(SUM(vp.UpvoteCount - vp.DownvoteCount), 0)
        FROM VotePatterns vp
        INNER JOIN Posts p ON vp.PostId = p.Id
        WHERE p.OwnerUserId = uam.Id
    ) AS NetVotes,
    CASE 
        WHEN uam.Reputation > 10000 THEN 'Elite'
        WHEN uam.Reputation > 5000 THEN 'Advanced'
        WHEN uam.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, uam.CreationDate)) AS YearsActive,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        INNER JOIN Posts p ON pl.PostId = p.Id
        WHERE p.OwnerUserId = uam.Id
            AND pl.LinkTypeId = 3
    ) AS DuplicateLinksReceived
FROM UserActivityMetrics uam
LEFT JOIN QuestionAnswerStats qas ON (uam.Id = qas.QuestionOwnerId OR uam.Id = qas.AnswerOwnerId)
WHERE qas.ResponseSpeed IS NOT NULL
    AND (qas.AvgAnswerScore > 2 OR qas.QuestionScore > 3)
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.PostId = qas.QuestionId 
            AND v.VoteTypeId IN (4, 12)
    )
GROUP BY 
    uam.Id,
    uam.DisplayName,
    uam.Location,
    uam.Reputation,
    uam.ReputationRank,
    uam.PostCount,
    uam.BadgeCount,
    uam.CreationDate
HAVING COUNT(DISTINCT qas.AnswerId) > 3
    OR COUNT(DISTINCT qas.QuestionId) > 2
ORDER BY 
    uam.Reputation DESC,
    AcceptanceRate DESC NULLS LAST,
    AvgViewCount DESC
LIMIT 500;
