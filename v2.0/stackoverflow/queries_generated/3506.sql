-- {"query": "3506.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3044} 

/*  Comprehensive benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, set operators, string ops and NULL logic                */
WITH UserQuestionStats AS (
    SELECT
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)              AS QuestionCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)             AS QuestionScore,
        MAX(p.CreationDate)                                    AS LastQuestionDate
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
UserAnswerStats AS (
    SELECT
        u.Id                                 AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)              AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)             AS AnswerScore,
        MAX(p.CreationDate)                                    AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 2
    GROUP BY u.Id
),
UserBadgePoints AS (
    SELECT
        b.UserId,
        SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END) AS BadgePoints,
        COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBadgeCount,
        COUNT(*) FILTER (WHERE b.TagBased = 0) AS NamedBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END) AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
TopTagPerUser AS (
    SELECT
        p.OwnerUserId                              AS UserId,
        tag,
        COUNT(*)                                   AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT TRIM(t) AS tag
        FROM regexp_split_to_table(p.Tags, '[><]') AS t
        WHERE t <> ''
    ) AS tags
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
Aggregated AS (
    SELECT
        COALESCE(uqs.UserId, uas.UserId)                AS UserId,
        COALESCE(uqs.DisplayName,
                 (SELECT DisplayName FROM Users WHERE Id = COALESCE(uqs.UserId, uas.UserId))) AS DisplayName,
        COALESCE(uqs.QuestionCount, 0)                  AS QuestionCount,
        COALESCE(uqs.QuestionScore, 0)                  AS QuestionScore,
        COALESCE(uas.AnswerCount, 0)                    AS AnswerCount,
        COALESCE(uas.AnswerScore, 0)                    AS AnswerScore,
        COALESCE(ubp.BadgePoints, 0)                    AS BadgePoints,
        COALESCE(uvs.UpVotesGiven, 0)                   AS UpVotesGiven,
        COALESCE(uvs.DownVotesGiven, 0)                 AS DownVotesGiven,
        COALESCE(uvs.FavoritesGiven, 0)                 AS FavoritesGiven,
        GREATEST(
            COALESCE(uqs.LastQuestionDate, TIMESTAMP '1970-01-01'),
            COALESCE(uas.LastAnswerDate,   TIMESTAMP '1970-01-01')
        )                                               AS LastActivity,
        tt.tag                                          AS TopTag,
        tt.TagUseCount
    FROM UserQuestionStats uqs
    FULL OUTER JOIN UserAnswerStats uas ON uas.UserId = uqs.UserId
    LEFT JOIN UserBadgePoints ubp      ON ubp.UserId = COALESCE(uqs.UserId, uas.UserId)
    LEFT JOIN UserVoteStats   uvs      ON uvs.UserId = COALESCE(uqs.UserId, uas.UserId)
    LEFT JOIN (
        SELECT UserId, tag, TagUseCount
        FROM TopTagPerUser
        WHERE rn = 1
    ) tt ON tt.UserId = COALESCE(uqs.UserId, uas.UserId)
)
SELECT
    a.UserId,
    a.DisplayName,
    a.QuestionCount,
    a.AnswerCount,
    a.BadgePoints,
    a.UpVotesGiven,
    a.DownVotesGiven,
    a.FavoritesGiven,
    a.TopTag,
    a.TagUseCount,
    a.LastActivity,
    RANK() OVER (ORDER BY
        (a.QuestionScore + a.AnswerScore) * 0.6
        + a.BadgePoints * 0.3
        + a.UpVotesGiven * 0.1 DESC)               AS ActivityRank,
    CASE
        WHEN a.LastActivity >= CURRENT_DATE - INTERVAL '30 days'  THEN 'Active'
        WHEN a.LastActivity >= CURRENT_DATE - INTERVAL '180 days' THEN 'Semi‑Active'
        ELSE 'Dormant'
    END                                            AS ActivityStatus,
    COALESCE(NULLIF(a.QuestionCount,0) / NULLIF(a.AnswerCount,0),0) AS QtoARatio
FROM Aggregated a
WHERE a.QuestionCount > 0

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    0                                            AS QuestionCount,
    0                                            AS AnswerCount,
    COALESCE(ubp.BadgePoints,0)                 AS BadgePoints,
    0                                            AS UpVotesGiven,
    0                                            AS DownVotesGiven,
    0                                            AS FavoritesGiven,
    NULL                                         AS TopTag,
    NULL                                         AS TagUseCount,
    NULL                                         AS LastActivity,
    RANK() OVER (ORDER BY COALESCE(ubp.BadgePoints,0) DESC) AS ActivityRank,
    'BadgeHero'                                  AS ActivityStatus,
    0                                            AS QtoARatio
FROM Users u
LEFT JOIN UserBadgePoints ubp ON ubp.UserId = u.Id
WHERE COALESCE(ubp.BadgePoints,0) >= 500
  AND NOT EXISTS (SELECT 1 FROM Aggregated agg WHERE agg.UserId = u.Id)

ORDER BY ActivityRank
LIMIT 100;
