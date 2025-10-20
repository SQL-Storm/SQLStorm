-- {"query": "9003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 2628} 

WITH
-- recent posts per user in the last year
RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.PostTypeId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentRank
    FROM Posts p
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '365 days'
),

-- badge counts by user broken out by class
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

-- explode tags string into tag + usage count
TagActivity AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS UsageCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
),

-- users with at least some badge activity
HighActivityUsers AS (
    SELECT
        u.Id       AS UserId,
        u.DisplayName,
        COALESCE(ubs.GoldBadges,0)   AS GoldBadges,
        COALESCE(ubs.SilverBadges,0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ubs.GoldBadges,0) + COALESCE(ubs.SilverBadges,0) + COALESCE(ubs.BronzeBadges,0) AS TotalBadges
    FROM Users u
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE COALESCE(ubs.GoldBadges,0) >= 1
       OR COALESCE(ubs.SilverBadges,0) >= 5
),

-- intersect active badge earners with users who posted recently
CombinedSet AS (
    SELECT UserId, 'BadgeActive'   AS Flag FROM HighActivityUsers
    INTERSECT
    SELECT OwnerUserId AS UserId, 'RecentPoster' AS Flag
      FROM RecentPosts WHERE RecentRank = 1
)

SELECT
    ha.DisplayName,
    ha.TotalBadges,
    rp.CreationDate                                    AS LastPostDate,
    COALESCE(vt.UpVotes,0) - COALESCE(vt.DownVotes,0)  AS VoteDelta,
    CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE u.Location END AS Location,
    ta.Tag,
    ta.UsageCount,
    -- correlated subquery counting comments after the last post
    (SELECT COUNT(*) 
       FROM Comments c 
      WHERE c.UserId = ha.UserId 
        AND c.CreationDate > rp.CreationDate
    )                                                  AS CommentsAfterLastPost,
    DENSE_RANK() OVER (ORDER BY rp.Score DESC)         AS ScoreRank
FROM CombinedSet cs
JOIN HighActivityUsers ha ON cs.UserId = ha.UserId
JOIN RecentPosts rp
    ON ha.UserId = rp.OwnerUserId
   AND rp.RecentRank = 1
LEFT JOIN (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1
                 WHEN vt.Name = 'DownMod' THEN -1
                 ELSE 0 END)             AS NetVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)   AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
) vt ON vt.PostId = rp.Id
LEFT JOIN TagActivity ta
  ON ta.Tag = ANY(string_to_array(substring(rp.Tags,2,length(rp.Tags)-2), '><'))
LEFT JOIN Users u ON u.Id = ha.UserId
WHERE rp.Score > (
    SELECT AVG(p.Score)
      FROM Posts p
     WHERE p.PostTypeId = 1
)
GROUP BY
    ha.DisplayName,
    ha.TotalBadges,
    rp.CreationDate,
    vt.UpVotes,
    vt.DownVotes,
    u.Location,
    ta.Tag,
    ta.UsageCount,
    rp.Score
ORDER BY
    ha.TotalBadges DESC,
    ta.UsageCount DESC
LIMIT 50;
