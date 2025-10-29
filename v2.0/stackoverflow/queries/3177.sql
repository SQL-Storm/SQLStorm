-- {"query": "3177.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2619}
WITH UserBadgeCounts AS (
    SELECT 
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)                            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        COUNT(*)                              AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score)                          AS AvgScore,
        MAX(p.CreationDate)                   AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteRatios AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*)                              AS TotalVotes,
        CASE 
            WHEN COUNT(*) = 0 THEN NULL
            ELSE SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)
        END                                   AS UpVoteRatio
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
UserTagDiversity AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        COUNT(DISTINCT tag)                    AS DistinctTagCount
    FROM Posts p,
    LATERAL (
        SELECT TRIM(t) AS tag
        FROM (
            SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM p.Tags), '><') AS t
        ) s
    ) split_tags
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT 
        u.Id                                   AS UserId,
        MAX(CASE WHEN ph.CreationDate > DATE '2024-10-01' - INTERVAL '30' DAY THEN ph.CreationDate END) AS LastHistoryChange,
        MAX(CASE WHEN pl.CreationDate > DATE '2024-10-01' - INTERVAL '30' DAY THEN pl.CreationDate END) AS LastLinkChange
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
        AND ph.CreationDate > DATE '2024-10-01' - INTERVAL '30' DAY
    LEFT JOIN PostLinks pl ON pl.PostId IN (
                                SELECT Id FROM Posts WHERE OwnerUserId = u.Id
                             )
        AND pl.CreationDate > DATE '2024-10-01' - INTERVAL '30' DAY
    GROUP BY u.Id
),
AggregatedVoteRatio AS (
    SELECT UserId, AVG(UpVoteRatio) AS UpVoteRatio
    FROM UserVoteRatios
    GROUP BY UserId
)
SELECT
    ubc.UserId,
    ubc.DisplayName,
    ubc.Reputation,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    COALESCE(ups.TotalPosts, 0)               AS TotalPosts,
    COALESCE(ups.Questions, 0)                AS Questions,
    COALESCE(ups.Answers, 0)                  AS Answers,
    COALESCE(ups.AvgScore, 0)                 AS AvgPostScore,
    COALESCE(avr.UpVoteRatio, 0)              AS UpVoteRatio,
    COALESCE(utd.DistinctTagCount, 0)         AS DistinctTagCount,
    ra.LastHistoryChange,
    ra.LastLinkChange,
    ROW_NUMBER() OVER (ORDER BY ubc.Reputation DESC, ubc.TotalBadges DESC) AS ReputationRank
FROM UserBadgeCounts ubc
LEFT JOIN UserPostStats ups      ON ups.UserId = ubc.UserId
LEFT JOIN AggregatedVoteRatio avr ON avr.UserId = ubc.UserId
LEFT JOIN UserTagDiversity utd ON utd.UserId = ubc.UserId
LEFT JOIN RecentActivity ra    ON ra.UserId = ubc.UserId
WHERE ubc.Reputation > 10000
  AND (ubc.TotalBadges IS NOT NULL OR ubc.TotalBadges = 0)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0                                      AS TotalBadges,
    0                                      AS GoldBadges,
    0                                      AS SilverBadges,
    0                                      AS BronzeBadges,
    0                                      AS TotalPosts,
    0                                      AS Questions,
    0                                      AS Answers,
    0                                      AS AvgPostScore,
    NULL                                   AS UpVoteRatio,
    0                                      AS DistinctTagCount,
    NULL                                   AS LastHistoryChange,
    NULL                                   AS LastLinkChange,
    NULL                                   AS ReputationRank
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)
  AND u.Reputation > 10000
ORDER BY Reputation DESC, TotalBadges DESC
LIMIT 100;