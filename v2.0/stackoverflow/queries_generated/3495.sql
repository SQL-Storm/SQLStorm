-- {"query": "3495.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1643} 

WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(NULLIF(p.Score,0)) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBased
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(*) AS TotalVotesCast,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyStarted
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
RecentActiveUsers AS (
    SELECT u.Id
    FROM Users u
    WHERE u.LastAccessDate >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT
    up.UserId,
    up.DisplayName,
    up.TotalPosts,
    up.Questions,
    up.Answers,
    up.AvgScore,
    ub.TotalBadges,
    ub.Gold,
    ub.Silver,
    ub.Bronze,
    ub.TagBased,
    uv.TotalVotesCast,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.BountyStarted,
    CASE
        WHEN up.LastPostDate IS NULL THEN 'Never posted'
        ELSE to_char(up.LastPostDate,'YYYY-MM-DD')
    END AS LastPostDateStr,
    CASE WHEN ru.Id IS NOT NULL THEN 1 ELSE 0 END AS IsRecentlyActive,
    COALESCE((
        SELECT STRING_AGG(DISTINCT t.TagName, ',')
        FROM Posts p
        JOIN LATERAL unnest(string_to_array(p.Tags, '><')) AS tag(tag) ON TRUE
        JOIN Tags t ON t.TagName = tag.tag
        WHERE p.OwnerUserId = up.UserId
          AND p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ), '') AS TopTags
FROM UserPostStats up
LEFT JOIN UserBadgeStats ub ON ub.UserId = up.UserId
LEFT JOIN UserVoteStats uv ON uv.UserId = up.UserId
LEFT JOIN RecentActiveUsers ru ON ru.Id = up.UserId
WHERE (up.TotalPosts > 0 OR ub.TotalBadges > 0)
ORDER BY (up.TotalPosts * COALESCE(ub.TotalBadges,0)) DESC
LIMIT 100
OFFSET 0

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
