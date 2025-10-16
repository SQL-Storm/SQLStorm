-- {"query": "25099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2647} 
WITH
UserAgg AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS ACount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAScore,
           MAX(p.CreationDate) AS LastPostDt,
           COALESCE(SUM(CASE WHEN b.Class = 1 THEN 100
                            WHEN b.Class = 2 THEN 10
                            ELSE 1 END),0) AS BadgePoints
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
    SELECT v.UserId,
           COUNT(*) AS RecentVoteCnt,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS RecentUpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS RecentDownVotes,
           MAX(v.CreationDate) AS LastVoteDt
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY v.UserId
),
TopUsers AS (
    SELECT ua.*,
           ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.BadgePoints DESC) AS rn
    FROM UserAgg ua
    WHERE ua.Reputation >= 2000
),
TagPopularity AS (
    SELECT t.TagName,
           COUNT(p.Id) AS TaggedPostCnt
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%' || t.TagName || '%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 150
),
UserTagScore AS (
    SELECT tu.Id,
           SUM(tp.TaggedPostCnt) AS TotalTaggedPosts
    FROM TopUsers tu
    LEFT JOIN Posts p ON p.OwnerUserId = tu.Id
    LEFT JOIN TagPopularity tp ON p.Tags LIKE ('%' || tp.TagName || '%')
    WHERE tu.rn <= 10
    GROUP BY tu.Id
)
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.QCount,
    tu.ACount,
    ROUND(tu.AvgQScore, 2) AS AvgQScore,
    ROUND(tu.AvgAScore, 2) AS AvgAScore,
    tu.LastPostDt,
    tu.BadgePoints,
    COALESCE(ra.RecentVoteCnt, 0) AS RecentVoteCnt,
    COALESCE(ra.RecentUpVotes, 0) AS RecentUpVotes,
    COALESCE(ra.RecentDownVotes, 0) AS RecentDownVotes,
    ra.LastVoteDt,
    COALESCE(uts.TotalTaggedPosts, 0) AS TaggedPostsFromPopularTags
FROM TopUsers tu
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
LEFT JOIN UserTagScore uts ON uts.Id = tu.Id
WHERE tu.rn <= 10
ORDER BY tu.Reputation DESC, tu.BadgePoints DESC
UNION ALL
SELECT
    NULL AS Id,
    '--- Tag Summary ---' AS DisplayName,
    NULL AS Reputation,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    SUM(tp.TaggedPostCnt) AS TaggedPostsFromPopularTags
FROM TagPopularity tp
WHERE NOT EXISTS (SELECT 1 FROM TopUsers WHERE rn <= 10);