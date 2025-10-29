-- {"query": "3956.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2816}
WITH
RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
),

UserAggregates AS (
    SELECT
        u.Id                                   AS UserId,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date)                           AS LastBadgeDate,
        u.UpVotes,
        u.DownVotes
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId      = u.Id
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
),

CloseReasonStats AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INTEGER) END) AS CloseReasonId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END)        AS CloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),

TagPopularity AS (
    SELECT
        t.TagName,
        t.Count                               AS TagUseCount,
        COALESCE(e.ExcerptLength,0)           AS ExcerptLength,
        COALESCE(w.WikiLength,0)              AS WikiLength
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS ExcerptLength
        FROM Posts p
        WHERE p.Id = t.ExcerptPostId
    ) e ON TRUE
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS WikiLength
        FROM Posts p
        WHERE p.Id = t.WikiPostId
    ) w ON TRUE
    WHERE t.IsModeratorOnly = FALSE
),

TopTagUsers AS (
    SELECT
        ua.UserId,
        STRING_AGG(tp.TagName, ', ' ORDER BY tp.Count DESC) AS TopTags
    FROM UserAggregates ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS TagRaw
    ) t_raw
    JOIN Tags tp ON tp.TagName = TRIM(BOTH '<>' FROM t_raw.TagRaw)
    GROUP BY ua.UserId
    HAVING COUNT(*) > 5
)

SELECT
    ua.UserId,
    u.DisplayName,
    ua.Reputation,
    ua.NetVotes,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    COALESCE(ttu.TopTags, 'None')                      AS TopTags,
    COALESCE(crs.CloseReasonId, 0)                     AS LastCloseReasonId,
    COALESCE(crs.CloseDate, CAST('1970-01-01' AS TIMESTAMP))    AS LastCloseDate,
    ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC,
                                 ua.NetVotes DESC) AS RankByRep,
    CASE
        WHEN ua.Reputation > 20000 THEN 'Elite'
        WHEN ua.Reputation BETWEEN 10000 AND 20000 THEN 'PowerUser'
        WHEN ua.Reputation BETWEEN 5000  AND 9999  THEN 'Experienced'
        ELSE 'Newbie'
    END                                                AS ReputationTier,
    (SELECT COUNT(*) FROM Votes v
        WHERE v.UserId = ua.UserId AND v.VoteTypeId = 2) AS UpVoteGiven,
    (SELECT COUNT(*) FROM Votes v
        WHERE v.UserId = ua.UserId AND v.VoteTypeId = 3) AS DownVoteGiven
FROM UserAggregates ua
JOIN Users u          ON u.Id = ua.UserId
LEFT JOIN TopTagUsers ttu   ON ttu.UserId = ua.UserId
LEFT JOIN CloseReasonStats crs
       ON crs.PostId = (
           SELECT p2.Id
           FROM Posts p2
           WHERE p2.OwnerUserId = ua.UserId
             AND p2.PostTypeId = 1
           ORDER BY p2.CreationDate DESC
           LIMIT 1
       )
WHERE ua.Reputation > 1000
  AND (ua.QuestionCount + ua.AnswerCount) > 10

UNION ALL

SELECT
    -1                                              AS UserId,
    'Aggregate Summary'                             AS DisplayName,
    SUM(ua.Reputation)                              AS Reputation,
    SUM(ua.NetVotes)                                AS NetVotes,
    SUM(ua.QuestionCount)                           AS QuestionCount,
    SUM(ua.AnswerCount)                             AS AnswerCount,
    SUM(ua.GoldBadges)                              AS GoldBadges,
    SUM(ua.SilverBadges)                            AS SilverBadges,
    SUM(ua.BronzeBadges)                            AS BronzeBadges,
    CAST(NULL AS text)                               AS TopTags,
    CAST(NULL AS integer)                            AS LastCloseReasonId,
    CAST(NULL AS timestamp)                          AS LastCloseDate,
    CAST(NULL AS integer)                            AS RankByRep,
    CAST(NULL AS text)                               AS ReputationTier,
    CAST(NULL AS integer)                            AS UpVoteGiven,
    CAST(NULL AS integer)                            AS DownVoteGiven
FROM UserAggregates ua
WHERE ua.Reputation > 1000
  AND (ua.QuestionCount + ua.AnswerCount) > 10

ORDER BY Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;