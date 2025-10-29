-- {"query": "3218.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2115} 
WITH UserBadgeAgg AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           COUNT(b.Id)                               AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentPosts AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.Title,
           p.Score,
           p.CreationDate,
           p.Tags,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1                                          -- only questions
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '90 days'
),
UserPostStats AS (
    SELECT u.Id AS UserId,
           COALESCE(AVG(p.Score), 0) AS AvgScore,
           COUNT(p.Id)               AS PostCount,
           MAX(p.CreationDate)       AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    GROUP BY u.Id
),
TagRanks AS (
    SELECT p.Id,
           tag,
           RANK() OVER (PARTITION BY tag ORDER BY p.Score DESC) AS TagScoreRank,
           p.Score
    FROM (
        SELECT p.Id,
               p.Score,
               UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) p
),
TopTagPosts AS (
    SELECT tr.Id,
           tr.tag AS Tag,
           tr.TagScoreRank,
           tr.Score,
           p.Title,
           p.OwnerUserId
    FROM TagRanks tr
    JOIN Posts p ON p.Id = tr.Id
    WHERE tr.TagScoreRank = 1
)
SELECT
    uba.UserId,
    uba.DisplayName,
    uba.Reputation,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    ups.AvgScore,
    ups.PostCount,
    COALESCE(rp.Title, 'No recent post')               AS RecentTitle,
    rp.CreationDate                                   AS RecentPostDate,
    CASE
        WHEN ups.PostCount = 0 THEN NULL
        ELSE (SELECT COUNT(*) FROM Posts p2
              WHERE p2.OwnerUserId = uba.UserId
                AND p2.Score > ups.AvgScore)
    END                                              AS HigherScorePostCount,
    tt.Tag,
    tt.Score                                          AS TopTagScore,
    tt.Title                                          AS TopTagPostTitle
FROM UserBadgeAgg uba
LEFT JOIN UserPostStats ups       ON ups.UserId = uba.UserId
LEFT JOIN RecentPosts rp          ON rp.OwnerUserId = uba.UserId AND rp.rn = 1
LEFT JOIN (
    SELECT ttp.OwnerUserId, ttp.Tag, ttp.Score, ttp.Title
    FROM TopTagPosts ttp
) tt                             ON tt.OwnerUserId = uba.UserId
WHERE uba.Reputation > 1000
   OR uba.TotalBadges >= 10

UNION ALL

SELECT
    NULL                                            AS UserId,
    'Aggregate Summary'                             AS DisplayName,
    NULL                                            AS Reputation,
    SUM(uba.GoldBadges)                             AS GoldBadges,
    SUM(uba.SilverBadges)                           AS SilverBadges,
    SUM(uba.BronzeBadges)                           AS BronzeBadges,
    AVG(ups.AvgScore)                               AS AvgScore,
    SUM(ups.PostCount)                              AS PostCount,
    NULL                                            AS RecentTitle,
    NULL                                            AS RecentPostDate,
    NULL                                            AS HigherScorePostCount,
    NULL                                            AS Tag,
    NULL                                            AS TopTagScore,
    NULL                                            AS TopTagPostTitle
FROM UserBadgeAgg uba
JOIN UserPostStats ups ON ups.UserId = uba.UserId
WHERE uba.Reputation > 5000

ORDER BY Reputation DESC NULLS LAST, GoldBadges DESC;