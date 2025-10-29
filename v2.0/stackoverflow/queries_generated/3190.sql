-- {"query": "3190.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2593} 

WITH
    /* Count badges per user, split by class */
    UserBadgeCounts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS BronzeBadges,
            COUNT(*)                                        AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Aggregate post statistics per user */
    UserPostStats AS (
        SELECT
            p.OwnerUserId                                   AS UserId,
            COUNT(*)        FILTER (WHERE p.PostTypeId = 1) AS Questions,
            COUNT(*)        FILTER (WHERE p.PostTypeId = 2) AS Answers,
            SUM(p.Score)                                   AS TotalScore,
            MAX(p.CreationDate)                            AS LastPostDate,
            COUNT(DISTINCT
                CASE WHEN p.Tags IS NOT NULL
                     THEN regexp_split_to_table(p.Tags, '><')
                END)                                      AS DistinctTagCount
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    /* Top 20 tags by overall count */
    TopTags AS (
        SELECT
            t.TagName,
            t.Count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),

    /* Votes in the last 30 days per post */
    RecentVotes AS (
        SELECT
            v.PostId,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
            MAX(v.CreationDate)                      AS LastVoteDate
        FROM Votes v
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY v.PostId
    ),

    /* Combine user‑level activity */
    UserActivity AS (
        SELECT
            u.Id                                  AS UserId,
            COALESCE(ubc.TotalBadges, 0)          AS BadgeCount,
            COALESCE(ups.Questions, 0)            AS QCount,
            COALESCE(ups.Answers, 0)              AS ACount,
            COALESCE(ups.TotalScore, 0)           AS ScoreSum,
            COALESCE(rv.UpVotes, 0)               AS RecentUpVotes,
            COALESCE(rv.DownVotes, 0)             AS RecentDownVotes,
            ROW_NUMBER() OVER (
                ORDER BY
                    COALESCE(ups.TotalScore, 0) +
                    COALESCE(rv.UpVotes, 0) * 5 -
                    COALESCE(rv.DownVotes, 0) * 2 DESC
            )                                    AS RankScore
        FROM Users u
        LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
        LEFT JOIN UserPostStats   ups ON ups.UserId = u.Id
        LEFT JOIN (
            SELECT
                p.OwnerUserId AS UserId,
                SUM(rv.UpVotes)   AS UpVotes,
                SUM(rv.DownVotes) AS DownVotes
            FROM Posts p
            LEFT JOIN RecentVotes rv ON rv.PostId = p.Id
            GROUP BY p.OwnerUserId
        ) rv ON rv.UserId = u.Id
        WHERE u.Reputation > 1000
          AND (u.Location IS NOT NULL OR u.AboutMe ILIKE '%SQL%')
    )

SELECT
    ua.RankScore,
    CONCAT(u.DisplayName, ' (', CAST(u.Id AS varchar), ')') AS UserInfo,
    u.Reputation,
    ua.QCount,
    ua.ACount,
    ua.ScoreSum,
    ua.BadgeCount,
    ua.RecentUpVotes,
    ua.RecentDownVotes,
    CASE
        WHEN ua.QCount = 0 THEN NULL
        ELSE ROUND(ua.ACount::numeric / ua.QCount, 2)
    END                                          AS AnswerRatio,
    STRING_AGG(DISTINCT tt.TagName, ', ') FILTER (WHERE tt.rn <= 5) AS TopTagsSample
FROM UserActivity ua
JOIN Users u ON u.Id = ua.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        regexp_split_to_table(p.Tags, '><') AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
) pt ON pt.OwnerUserId = u.Id
LEFT JOIN TopTags tt ON tt.TagName = pt.Tag
GROUP BY
    ua.RankScore,
    u.Id,
    u.DisplayName,
    u.Reputation,
    ua.QCount,
    ua.ACount,
    ua.ScoreSum,
    ua.BadgeCount,
    ua.RecentUpVotes,
    ua.RecentDownVotes
HAVING COUNT(DISTINCT tt.TagName) > 0

UNION ALL

/* Aggregated summary row for the top‑10 ranked users */
SELECT
    NULL                                    AS RankScore,
    'Aggregated Summary'                    AS UserInfo,
    NULL                                    AS Reputation,
    SUM(ua.QCount)                          AS Questions,
    SUM(ua.ACount)                          AS Answers,
    SUM(ua.ScoreSum)                        AS TotalScore,
    SUM(ua.BadgeCount)                      AS Badges,
    SUM(ua.RecentUpVotes)                   AS UpVotes30d,
    SUM(ua.RecentDownVotes)                 AS DownVotes30d,
    NULL                                    AS AnswerRatio,
    NULL                                    AS TopTagsSample
FROM UserActivity ua
WHERE ua.RankScore <= 10;
