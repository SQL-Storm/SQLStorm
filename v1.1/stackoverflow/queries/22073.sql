-- {"query": "22073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 557} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        COALESCE(u.WebsiteUrl, '') AS Website,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location, u.WebsiteUrl
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS Edits,
        MAX(p.LastActivityDate) AS LastActivity,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ',') AS TagList
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6) -- Edit types
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY (Reputation * (1 + UpvotesReceived) / NULLIF(1 + DownvotesReceived, 0) + COALESCE(AvgPostScore, 0)) DESC) AS Rank
    FROM UserStats us
    LEFT JOIN PostActivity pa ON us.Id = pa.OwnerUserId
    WHERE BadgeCount > 0 AND TotalPosts > 10
)
SELECT ru.*,
    CASE 
        WHEN ru.LastActivity > cast('2024-10-01' as date) - INTERVAL '30 days' THEN 'Active'
        WHEN ru.LastActivity IS NULL THEN 'No Activity'
        ELSE 'Inactive'
    END AS ActivityStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ru.Id AND c.Score > 5) AS HighScoreComments
FROM RankedUsers ru
WHERE Rank <= 10
ORDER BY Rank;