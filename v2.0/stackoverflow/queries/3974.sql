-- {"query": "3974.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2467}
WITH
    UserStats AS (
        SELECT
            u.Id                                            AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.Location, 'Unknown')                AS Location,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)   AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)   AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
            (
                SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p2.Score)
                FROM Posts p2
                WHERE p2.OwnerUserId = u.Id AND p2.Score IS NOT NULL
            ) AS P90Score,
            SUM(COALESCE(p.ViewCount, 0))                  AS TotalViews,
            (
                SELECT COUNT(DISTINCT TRIM(BOTH '<>' FROM t_raw))
                FROM (
                    SELECT UNNEST(string_to_array(COALESCE(p2.Tags, ''), '><')) AS t_raw
                    FROM Posts p2
                    WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
                ) tags
                WHERE tags.t_raw <> ''
            ) AS DistinctTagsAnswered
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    ),
    BadgeCounts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)  AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)  AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)  AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    TopTagPerUser AS (
        SELECT
            us.UserId,
            tag.TagName,
            ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY tag.cnt DESC) AS rn
        FROM UserStats us
        CROSS JOIN LATERAL (
            SELECT
                TRIM(BOTH '<>' FROM t)            AS TagName,
                COUNT(*)                          AS cnt
            FROM (
                SELECT UNNEST(string_to_array(COALESCE(p.Tags, ''), '><')) AS t
                FROM Posts p
                WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 2
            ) sub
            WHERE t <> ''
            GROUP BY TRIM(BOTH '<>' FROM t)
        ) tag
    ),
    UserVotes AS (
        SELECT
            p.OwnerUserId                                   AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    )
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgScore,
    us.P90Score,
    us.TotalViews,
    us.DistinctTagsAnswered,
    COALESCE(bc.GoldBadges,   0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uv.UpVotesReceived,   0) - COALESCE(uv.DownVotesReceived, 0) AS NetVotesReceived,
    CASE
        WHEN us.QuestionCount = 0 AND us.AnswerCount = 0 THEN 'Silent'
        WHEN us.Reputation > 20000                     THEN 'HighRep'
        ELSE 'Active'
    END                                             AS UserTier,
    tt.TagName                                      AS TopAnsweredTag
FROM UserStats us
LEFT JOIN BadgeCounts bc   ON bc.UserId = us.UserId
LEFT JOIN UserVotes uv    ON uv.UserId = us.UserId
LEFT JOIN TopTagPerUser tt ON tt.UserId = us.UserId AND tt.rn = 1
WHERE us.Reputation IS NOT NULL

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, 'Unknown') AS Location,
    0, 0, NULL, NULL, 0, 0,
    0, 0, 0,
    0,
    'NoPosts' AS UserTier,
    NULL AS TopAnsweredTag
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id);