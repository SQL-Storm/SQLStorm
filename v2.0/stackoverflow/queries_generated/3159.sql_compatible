WITH top_tags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),
user_tag_stats AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        tg.TagName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        SUM(COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) AS NetScore,
        ROW_NUMBER() OVER (PARTITION BY tg.TagName
                           ORDER BY SUM(COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) DESC) AS TagRank
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) AS pt ON TRUE
    LEFT JOIN Tags tg
        ON tg.TagName = pt.tag
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt
            ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) v
        ON v.PostId = p.Id
    WHERE u.Reputation IS NOT NULL
    GROUP BY u.Id, u.DisplayName, tg.TagName
),
badge_agg AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ',') AS Badges,
        MAX(b.Class)                     AS HighestBadgeClass
    FROM Badges b
    GROUP BY b.UserId
),
recent_closed AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate)                                     AS LastClosedDate,
        MAX(CASE WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS INTEGER) END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT
    uts.UserId,
    uts.DisplayName,
    uts.TagName,
    uts.QuestionsAsked,
    uts.AnswersGiven,
    uts.NetScore,
    uts.TagRank,
    ba.Badges,
    ba.HighestBadgeClass,
    rc.LastClosedDate,
    cr.Name                                                   AS CloseReason,
    CASE
        WHEN uts.NetScore > 1000 THEN 'Power User'
        WHEN uts.NetScore BETWEEN 500 AND 1000 THEN 'Active Contributor'
        ELSE 'Participant'
    END                                                      AS UserTier,
    COALESCE(uts.NetScore * 0.1, 0) + COALESCE(ba.HighestBadgeClass * 10, 0) AS CompositeScore
FROM user_tag_stats uts
LEFT JOIN badge_agg ba
    ON ba.UserId = uts.UserId
LEFT JOIN recent_closed rc
    ON rc.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = uts.UserId
          AND p.PostTypeId = 1
          AND p.Tags LIKE '%' || uts.TagName || '%'
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN CloseReasonTypes cr
    ON cr.Id = rc.CloseReasonId
WHERE uts.TagRank <= 10
  AND (uts.NetScore IS NOT NULL OR ba.Badges IS NOT NULL)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    NULL                 AS TagName,
    NULL                 AS QuestionsAsked,
    NULL                 AS AnswersGiven,
    NULL                 AS NetScore,
    NULL                 AS TagRank,
    ba.Badges,
    ba.HighestBadgeClass,
    NULL                 AS LastClosedDate,
    NULL                 AS CloseReason,
    CASE
        WHEN u.Reputation > 20000 THEN 'Legendary'
        WHEN u.Reputation > 10000 THEN 'Expert'
        ELSE 'Member'
    END                  AS UserTier,
    u.Reputation * 0.05 AS CompositeScore
FROM Users u
LEFT JOIN badge_agg ba
    ON ba.UserId = u.Id
WHERE u.CreationDate > CAST('2020-01-01' AS TIMESTAMP)
  AND u.Reputation IS NOT NULL
ORDER BY CompositeScore DESC
LIMIT 100;