-- {"query": "9036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3829} 
WITH ActiveBadges AS (
    SELECT
        UserId,
        COUNT(*) AS BadgeCount,
        AVG(CASE WHEN Class = 1 THEN 3 WHEN Class = 2 THEN 2 ELSE 1 END) AS AvgBadgeClass
    FROM Badges
    GROUP BY UserId
),
Recent30 AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
),
TopRecent AS (
    SELECT Id, OwnerUserId, Score, ViewCount
    FROM Recent30
    WHERE RN <= 3
),
TagsExploded AS (
    SELECT
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.PostTypeId = 1
    WHERE p.Tags IS NOT NULL
),
TopTags AS (
    SELECT Tag
    FROM TagsExploded
    GROUP BY Tag
    HAVING COUNT(*) > 5
    ORDER BY COUNT(*) DESC
    LIMIT 10
),
UserTagScores AS (
    SELECT
        te.UserId,
        te.Tag,
        SUM(COALESCE(p.Score, 0) / NULLIF(p.ViewCount, 0)) AS ScorePerView
    FROM TagsExploded te
    JOIN Posts p
        ON p.OwnerUserId = te.UserId
       AND p.PostTypeId = 1
    WHERE te.Tag IN (SELECT Tag FROM TopTags)
    GROUP BY te.UserId, te.Tag
),
SetFilter AS (
    SELECT UserId FROM ActiveBadges WHERE BadgeCount > 10
    UNION
    SELECT UserId
    FROM (
        SELECT UserId, SUM(ScorePerView) AS TotalSPV
        FROM UserTagScores
        GROUP BY UserId
    ) t
    WHERE TotalSPV > 0.1
    EXCEPT
    SELECT UserId
    FROM Votes
    WHERE VoteTypeId = 3
),
Summary AS (
    SELECT
        u.Id,
        u.DisplayName,
        ab.BadgeCount,
        sp.TotalSPV,
        COALESCE(a.TotalQuestions, 0) AS TotalQ,
        COALESCE(a.TotalAnswers,   0) AS TotalA
    FROM Users u
    LEFT JOIN ActiveBadges ab
        ON ab.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, SUM(ScorePerView) AS TotalSPV
        FROM UserTagScores
        GROUP BY UserId
    ) sp
        ON sp.UserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId AS UserId,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
        FROM Posts p
        GROUP BY p.OwnerUserId
    ) a
        ON a.UserId = u.Id
    WHERE u.Id IN (SELECT UserId FROM SetFilter)
)
SELECT
    s.*,
    COALESCE(lc.LastComment, '-')                   AS LastAnswerComment,
    (SELECT AVG(CASE WHEN v.VoteTypeId = 2 THEN 1
                     WHEN v.VoteTypeId = 3 THEN -1
                     ELSE 0 END)
     FROM Votes v
     WHERE v.UserId = s.Id)                         AS AvgVoteBalance,
    CASE
        WHEN s.TotalSPV > 1   THEN 'High'
        WHEN s.TotalSPV > 0.5 THEN 'Med'
        ELSE 'Low'
    END                                              AS Engagement,
    ROW_NUMBER() OVER (ORDER BY s.BadgeCount DESC, s.TotalSPV DESC) AS RankGlobal,
    pe.LastEdit
FROM Summary s
LEFT JOIN LATERAL (
    SELECT c.Text AS LastComment
    FROM Comments c
    JOIN Posts p2
      ON p2.Id = c.PostId
    WHERE p2.OwnerUserId = s.Id
      AND p2.PostTypeId   = 2
    ORDER BY c.CreationDate DESC
    LIMIT 1
) lc ON TRUE
LEFT JOIN LATERAL (
    SELECT MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.UserId = s.Id
) pe ON TRUE
ORDER BY s.TotalSPV DESC, s.BadgeCount DESC;