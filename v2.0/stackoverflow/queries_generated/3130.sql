-- {"query": "3130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2432} 

WITH UserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(b.Class),0)                AS BadgeScore,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

RecentActivePosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

TagUsage AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                     AS QuestionCount,
        SUM(p.Score)                    AS TotalScore,
        AVG(p.ViewCount)                AS AvgViews,
        MAX(p.CreationDate)             AS LastUsed
    FROM Tags t
    JOIN Posts p
      ON p.Tags IS NOT NULL
     AND t.TagName = ANY(string_to_array(trim(both '<>' FROM p.Tags), '><'))
    WHERE p.PostTypeId = 1               -- only questions
    GROUP BY t.TagName
),

UserVoteSummary AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Id = 2)                     AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Id = 3)                     AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Id = 1)                     AS Accepted,
        SUM(CASE WHEN vt.Id = 8 THEN v.BountyAmount ELSE 0 END) AS BountyStarted,
        SUM(CASE WHEN vt.Id = 9 THEN v.BountyAmount ELSE 0 END) AS BountyAwarded
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),

ClosedDuplicateInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
        MAX(CASE WHEN ph.PostHistoryTypeId = 3  THEN ph.Text    END) AS DuplicateTargetsJson
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,3)
    GROUP BY ph.PostId
)

SELECT
    ur.Id                                 AS UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.BadgeScore,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0)        AS NetVotes,
    COALESCE(vs.BountyAwarded,0) - COALESCE(vs.BountyStarted,0) AS NetBounty,
    rp.Title,
    rp.Score                              AS PostScore,
    rp.ViewCount,
    rp.CreationDate                       AS PostCreated,
    COALESCE(tu.TagName,'<no-tag>')       AS TopTag,
    tu.QuestionCount,
    tu.TotalScore,
    tu.AvgViews,
    cd.CloseReason,
    CASE
        WHEN cd.DuplicateTargetsJson IS NOT NULL THEN jsonb_array_length(cd.DuplicateTargetsJson::jsonb)
        ELSE 0
    END                                   AS DuplicateCount,
    ROW_NUMBER() OVER (PARTITION BY ur.Id ORDER BY rp.Score DESC NULLS LAST) AS PostRankByScore,
    CASE
        WHEN rp.Score > 0 AND rp.ViewCount > 1000 THEN 'Hot'
        WHEN rp.Score < 0                                   THEN 'Unpopular'
        ELSE                                                'Normal'
    END                                 AS PostHeatCategory,
    CONCAT('https://stackoverflow.com/q/', rp.Id) AS PostUrl
FROM UserReputation ur
LEFT JOIN UserVoteSummary vs   ON vs.UserId = ur.Id
LEFT JOIN RecentActivePosts rp ON rp.OwnerUserId = ur.Id AND rp.rn = 1
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        t.QuestionCount,
        t.TotalScore,
        t.AvgViews
    FROM TagUsage t
    WHERE rp.Tags IS NOT NULL
      AND t.TagName = ANY(string_to_array(trim(both '<>' FROM rp.Tags), '><'))
    ORDER BY t.QuestionCount DESC
    LIMIT 1
) tu ON TRUE
LEFT JOIN ClosedDuplicateInfo cd ON cd.PostId = rp.Id
WHERE ur.Reputation > 1000
  AND (rp.Score IS NOT NULL OR rp.Title IS NOT NULL)
ORDER BY ur.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL
WHERE FALSE;
