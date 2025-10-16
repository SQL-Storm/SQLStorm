-- {"query": "13050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 577} 

WITH UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionsAsked,
        AnswersProvided,
        LastPostDate,
        AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY AvgPostScore DESC, TotalPosts DESC) AS Rank
    FROM
        UserActivity
    WHERE
        TotalPosts >= 10
)
SELECT
    tc.DisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.QuestionsAsked,
    tc.AnswersProvided,
    tc.AvgPostScore,
    ph.CreationDate AS LastEditDate,
    ph.Comment AS LastEditComment,
    b.Name AS LatestBadge,
    COALESCE(NULLIF(TRIM(u.Location), ''), 'Unknown') AS UserLocation
FROM
    TopContributors tc
LEFT JOIN
    LATERAL (
        SELECT
            ph.CreationDate,
            ph.Comment
        FROM
            PostHistory ph
        WHERE
            ph.UserId = tc.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
        ORDER BY
            ph.CreationDate DESC
        LIMIT 1
    ) ph ON true
LEFT JOIN
    Badges b ON tc.Id = b.UserId AND b.Class = 1
LEFT JOIN
    Users u ON tc.Id = u.Id
WHERE
    tc.Rank <= 10
    AND b.Date >= CURRENT_DATE - INTERVAL '6 months'
ORDER BY
    tc.Rank, tc.AvgPostScore DESC;
