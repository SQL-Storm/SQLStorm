-- {"query": "3100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1904} 

WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(
            CASE 
                WHEN b.Class = 1 THEN 100      -- Gold
                WHEN b.Class = 2 THEN 50       -- Silver
                ELSE 10                         -- Bronze
            END),0)                         AS BadgePoints,
        COUNT(DISTINCT b.Id)                AS BadgeCount,
        COALESCE(SUM(p.Score),0)            AS TotalPostScore,
        COUNT(p.Id)                         AS PostCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate)                 AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TagUsage AS (
    SELECT 
        pu.OwnerUserId                         AS UserId,
        UNNEST(string_to_array(trim(both '<>' FROM pu.Tags), '><')) AS Tag,
        COUNT(*)                               AS TagCount
    FROM Posts pu
    WHERE pu.PostTypeId = 1                     -- only questions
      AND pu.Tags IS NOT NULL
    GROUP BY pu.OwnerUserId, Tag
),

TopTags AS (
    SELECT 
        t.UserId,
        STRING_AGG(t.Tag, ', ' ORDER BY t.TagCount DESC) AS Top3Tags
    FROM (
        SELECT 
            tu.*,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS rn
        FROM TagUsage tu
    ) t
    WHERE t.rn <= 3
    GROUP BY t.UserId
),

RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')      AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')    AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite')   AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

ClosedDuplicateQuestions AS (
    SELECT 
        ph.PostId,
        ph.CreationDate,
        (ph.Comment)::int                         AS ClosedReasonId,
        (ph.Text)::jsonb->'OriginalQuestionIds'   AS DuplicateIds
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10               -- Post Closed
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.BadgePoints,
    us.BadgeCount,
    us.PostCount,
    us.TotalPostScore,
    ROUND(us.AvgScore::numeric,2)                AS AvgScore,
    us.LastPostDate,
    COALESCE(tt.Top3Tags,'')                     AS TopTags,
    COALESCE(rv.UpVotes,0)                       AS UpVotesLast30d,
    COALESCE(rv.DownVotes,0)                     AS DownVotesLast30d,
    COALESCE(rv.Favorites,0)                     AS FavoritesLast30d,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation > 10000 THEN 'Pro'
        WHEN us.Reputation > 5000  THEN 'Intermediate'
        ELSE 'Novice' 
    END                                          AS ReputationTier,
    EXISTS (
        SELECT 1 
        FROM ClosedDuplicateQuestions cdq
        WHERE cdq.PostId = ANY (
            SELECT p.Id 
            FROM Posts p 
            WHERE p.OwnerUserId = us.Id 
              AND p.PostTypeId = 1
        )
    )                                            AS HasClosedOrDuplicate
FROM UserStats us
LEFT JOIN TopTags      tt ON tt.UserId = us.Id
LEFT JOIN RecentVotes  rv ON rv.UserId = us.Id
WHERE us.Reputation IS NOT NULL
ORDER BY us.BadgePoints DESC, us.Reputation DESC
LIMIT 100
OFFSET 0

UNION ALL

SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
ORDER BY 2 DESC
OFFSET 0 LIMIT 0;
