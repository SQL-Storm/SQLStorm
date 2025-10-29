-- {"query": "3223.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2359}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(u.AboutMe, '') AS AboutMe,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesGiven
    FROM Users u
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),
UserTagActivity AS (
    SELECT 
        us.Id AS UserId,
        STRING_AGG(DISTINCT pt.tag, ',') AS TopUserTags
    FROM UserStats us
    JOIN Posts p ON p.OwnerUserId = us.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS tag
    ) pt ON TRUE
    JOIN Tags t ON t.TagName = pt.tag
    GROUP BY us.Id
),
RecentPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN p.CreationDate > (DATE '2024-10-01' - INTERVAL '30 days') THEN 1 END) AS RecentPostCount,
        MAX(CASE WHEN p.CreationDate > (DATE '2024-10-01' - INTERVAL '30 days') THEN p.Score END) AS MaxRecentScore
    FROM Posts p
    GROUP BY p.OwnerUserId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.BadgeCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(uta.TopUserTags, '') AS TopUserTags,
    rp.RecentPostCount,
    rp.MaxRecentScore,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.GoldBadges DESC) AS ReputationRank,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Veteran'
        WHEN us.Reputation BETWEEN 5000  AND  9999 THEN 'Experienced'
        ELSE 'Newbie'
    END AS ReputationBucket,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.Id AND c.Score > 0) AS PositiveCommentCount,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = us.Id) AS LastVoteDate,
    COALESCE(us.LastAccessDate, TIMESTAMP '1970-01-01') AS LastAccessDate
FROM UserStats us
LEFT JOIN UserTagActivity uta ON uta.UserId = us.Id
LEFT JOIN RecentPosts rp       ON rp.OwnerUserId = us.Id
WHERE us.Reputation IS NOT NULL
  AND (us.GoldBadges > 0 OR us.SilverBadges > 0)
  AND (us.PostCount > 0 OR us.BadgeCount > 0)

UNION ALL

SELECT 
    -1                                   AS Id,
    'All Users Summary'                  AS DisplayName,
    SUM(us.Reputation)                   AS Reputation,
    SUM(us.PostCount)                    AS PostCount,
    SUM(us.BadgeCount)                   AS BadgeCount,
    SUM(us.GoldBadges)                   AS GoldBadges,
    SUM(us.SilverBadges)                 AS SilverBadges,
    SUM(us.BronzeBadges)                 AS BronzeBadges,
    ''                                   AS TopUserTags,
    SUM(rp.RecentPostCount)              AS RecentPostCount,
    MAX(rp.MaxRecentScore)               AS MaxRecentScore,
    CAST(NULL AS INTEGER)                AS ReputationRank,
    CAST(NULL AS VARCHAR)                AS ReputationBucket,
    SUM((SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.Id AND c.Score > 0)) AS PositiveCommentCount,
    MAX((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = us.Id))    AS LastVoteDate,
    CAST(NULL AS TIMESTAMP)              AS LastAccessDate
FROM UserStats us
LEFT JOIN RecentPosts rp ON rp.OwnerUserId = us.Id
WHERE us.Reputation IS NOT NULL
GROUP BY Id, DisplayName;