-- {"query": "20100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1530} 

WITH UserMetrics AS (
    -- CTE 1: Aggregate core metrics for high-reputation, recently active users.
    -- This identifies the pool of "power users" for further analysis.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        (EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / 86400.0) AS AccountAgeDays,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId AND p.CommunityOwnedDate IS NULL
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 15000 AND u.LastAccessDate > (NOW() - INTERVAL '2 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 5
        AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 5
),
PostAnalysis AS (
    -- CTE 2: Analyze the questions posted by the users identified above.
    -- It uses window functions to rank questions and calculates engagement metrics.
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        -- Calculate time to get an accepted answer, using a join back to the Posts table.
        EXTRACT(EPOCH FROM (aa.CreationDate - p.CreationDate)) / 3600.0 AS HoursToAcceptedAnswer,
        -- Correlated subquery to count edits on a post.
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        -- Rank questions for each user based on score and views.
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM
        Posts p
    -- Only analyze posts from our pre-filtered user pool.
    JOIN
        UserMetrics um ON p.OwnerUserId = um.UserId
    -- Outer join to handle questions without an accepted answer.
    LEFT JOIN
        Posts aa ON p.AcceptedAnswerId = aa.Id
    WHERE
        p.PostTypeId = 1 -- Questions only
),
UserActivityFrequency AS (
    -- CTE 3: Use a set operator (UNION ALL) to create a unified timeline of user actions.
    -- Then, use a window function (LAG) to calculate the time between consecutive actions.
    SELECT
        UserId,
        AVG(MinutesBetweenActions) AS AvgMinutesBetweenActions,
        COUNT(*) AS TotalActions
    FROM (
        SELECT
            UserId,
            EXTRACT(EPOCH FROM (ActionDate - LAG(ActionDate, 1) OVER (PARTITION BY UserId ORDER BY ActionDate))) / 60.0 AS MinutesBetweenActions
        FROM (
            SELECT OwnerUserId AS UserId, CreationDate AS ActionDate FROM Posts WHERE OwnerUserId IS NOT NULL
            UNION ALL
            SELECT UserId, CreationDate AS ActionDate FROM Comments WHERE UserId IS NOT NULL
            UNION ALL
            SELECT UserId, CreationDate AS ActionDate FROM Votes WHERE UserId IS NOT NULL AND VoteTypeId IN (2, 3, 5, 8)
        ) AS AllActions
    ) AS ActionIntervals
    -- Filter out noise (e.g., simultaneous actions or very long breaks).
    WHERE
        MinutesBetweenActions IS NOT NULL AND MinutesBetweenActions BETWEEN 0.1 AND 10080 -- 1 week
    GROUP BY
        UserId
)
-- Final SELECT: Combine data from all CTEs to generate a comprehensive report.
SELECT
    um.DisplayName,
    um.Reputation,
    um.AccountAgeDays,
    um.QuestionCount,
    um.AnswerCount,
    -- Complicated calculation for a composite "Influence Score".
    (um.Reputation / NULLIF(um.AccountAgeDays, 0)) + (um.GoldBadges * 100) + (uaf.TotalActions / 100.0) AS InfluenceScore,
    uaf.AvgMinutesBetweenActions,
    pa.Title AS TopQuestionTitle,
    pa.Score AS TopQuestionScore,
    pa.HoursToAcceptedAnswer,
    pa.EditCount AS TopQuestionEditCount,
    -- Complex CASE statement with string functions and NULL logic for geo-tagging.
    CASE
        WHEN um.Location IS NULL THEN 'Unknown'
        WHEN um.Location ILIKE '%Europe%' OR um.Location ILIKE '%UK%' OR um.Location ILIKE '%Germany%' OR um.Location ILIKE '%France%' THEN 'Europe'
        WHEN um.Location ILIKE '%USA%' OR um.Location ILIKE '%United States%' OR um.Location ILIKE '%Canada%' THEN 'North America'
        WHEN um.Location ILIKE '%India%' OR um.Location ILIKE '%China%' THEN 'Asia'
        ELSE 'Other'
    END AS UserRegion,
    -- Correlated subquery to find the name of the user's most recently awarded badge.
    (SELECT b.Name FROM Badges b WHERE b.UserId = um.UserId ORDER BY b.Date DESC LIMIT 1) AS LatestBadgeName
FROM
    UserMetrics um
JOIN
    UserActivityFrequency uaf ON um.UserId = uaf.UserId
LEFT JOIN
    -- Join only the top-ranked question for each user.
    PostAnalysis pa ON um.UserId = pa.OwnerUserId AND pa.QuestionRank = 1
WHERE
    uaf.AvgMinutesBetweenActions < 2880 -- Must have an average action frequency of less than 2 days.
    AND (pa.Score > 20 OR pa.Score IS NULL) -- Top question should be reasonably popular, or they might have no questions.
    AND um.DisplayName NOT LIKE 'user%' -- Exclude default usernames.
ORDER BY
    InfluenceScore DESC NULLS LAST,
    um.Reputation DESC
LIMIT 100;

