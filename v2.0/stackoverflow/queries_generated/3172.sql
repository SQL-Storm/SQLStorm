-- {"query": "3172.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2214} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                                   AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)   AS AvgScore,
        MAX(p.CreationDate)                               AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)   AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
GoldBadgeUsers AS (
    SELECT 
        b.UserId,
        COUNT(*) AS GoldBadgeCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),
TagInfo AS (
    SELECT 
        t.TagName,
        t.Count                     AS TagUseCount,
        COALESCE(e.Title, w.Title) AS TagTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*)                                    AS RecentVoteCount,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)  AS RecentUpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)  AS RecentDownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),
UserTagActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS PostsWithTag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.ReputationRank,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    ROUND(us.AvgScore, 2)                                     AS AvgScore,
    COALESCE(gb.GoldBadgeCount, 0)                            AS GoldBadgeCount,
    COALESCE(rv.RecentVoteCount, 0)                           AS RecentVoteCount,
    COALESCE(rv.RecentUpVotes, 0)                             AS RecentUpVotes,
    COALESCE(rv.RecentDownVotes, 0)                           AS RecentDownVotes,
    STRING_AGG(DISTINCT ti.TagName, ', ')
        FILTER (WHERE ti.TagUseCount > 1000)                 AS PopularTags,
    MAX(CASE WHEN ut.Tag IS NOT NULL THEN ut.Tag END)
        OVER (PARTITION BY us.Id 
              ORDER BY ut.PostsWithTag DESC 
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) 
                                                              AS TopTagByPosts,
    CASE
        WHEN us.ReputationRank <= 10  THEN 'Top10'
        WHEN us.ReputationRank <= 100 THEN 'Top100'
        ELSE 'Other'
    END                                                       AS ReputationTier,
    CASE 
        WHEN us.LastPostDate IS NULL                     THEN 'NeverPosted'
        WHEN us.LastPostDate < CURRENT_DATE - INTERVAL '1 year' THEN 'Stale'
        ELSE 'Active'
    END                                                       AS ActivityStatus
FROM UserStats us
LEFT JOIN GoldBadgeUsers gb   ON gb.UserId = us.Id
LEFT JOIN RecentVotes rv      ON rv.UserId = us.Id
LEFT JOIN UserTagActivity ut ON ut.UserId = us.Id
LEFT JOIN TagInfo ti          ON ti.TagName = ut.Tag
WHERE us.Reputation > 0
GROUP BY us.Id, us.DisplayName, us.Reputation, us.ReputationRank,
         us.TotalPosts, us.Questions, us.Answers, us.AvgScore,
         gb.GoldBadgeCount, rv.RecentVoteCount, rv.RecentUpVotes,
         rv.RecentDownVotes, us.LastPostDate
HAVING COUNT(DISTINCT ti.TagName) > 0
ORDER BY us.ReputationRank
LIMIT 100

UNION ALL

SELECT
    NULL,
    'Aggregate Summary',
    NULL,
    NULL,
    SUM(us.TotalPosts),
    SUM(us.Questions),
    SUM(us.Answers),
    ROUND(AVG(us.AvgScore), 2),
    SUM(gb.GoldBadgeCount),
    SUM(rv.RecentVoteCount),
    SUM(rv.RecentUpVotes),
    SUM(rv.RecentDownVotes),
    NULL,
    NULL,
    NULL,
    NULL
FROM UserStats us
LEFT JOIN GoldBadgeUsers gb   ON gb.UserId = us.Id
LEFT JOIN RecentVotes rv      ON rv.UserId = us.Id
WHERE us.Reputation > 0;
