-- {"query": "3931.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2067} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score,0)) AS TotalScore,
        SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopTagScore AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        SUM(p.Score) AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC) AS rn
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) AS ts ON true
    JOIN Tags t ON t.TagName = ts.tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
RecentVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    us.TotalViews,
    ba.TotalBadges,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.BadgeNames,
    tt.TagName,
    tt.TagScore,
    COALESCE(rv.UpVotes,0) AS RecentUpVotes,
    COALESCE(rv.DownVotes,0) AS RecentDownVotes,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
        ELSE 'Regular'
    END AS ReputationTier,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = us.Id 
       AND p2.CreationDate > us.LastPostDate) AS FuturePostsCount
FROM UserStats us
LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
LEFT JOIN (
    SELECT UserId, TagName, TagScore
    FROM TopTagScore
    WHERE rn = 1
) tt ON tt.UserId = us.Id
LEFT JOIN RecentVotes rv ON rv.PostId = (
    SELECT p3.Id
    FROM Posts p3
    WHERE p3.OwnerUserId = us.Id
    ORDER BY p3.CreationDate DESC
    LIMIT 1
)
WHERE (us.QuestionCount + us.AnswerCount) > 0
  AND (us.TotalScore IS NOT NULL OR us.TotalViews IS NOT NULL)
  AND EXISTS (
      SELECT 1 
      FROM Posts p4
      WHERE p4.OwnerUserId = us.Id
        AND p4.ClosedDate IS NULL
        AND (p4.Tags IS NULL OR p4.Tags NOT LIKE '%<javascript>%')
  )
UNION ALL
SELECT 
    -1 AS Id,
    'Community' AS DisplayName,
    NULL AS Reputation,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL,
    NULL, NULL,
    NULL, NULL,
    NULL,
    NULL,
    NULL,
    NULL
WHERE NOT EXISTS (SELECT 1 FROM Users);
