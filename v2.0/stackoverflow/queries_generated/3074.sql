-- {"query": "3074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2635} 

WITH
    usr AS (
        SELECT *
        FROM   Users
    ),

    post_stats AS (
        SELECT
            p.OwnerUserId                                     AS UserId,
            COUNT(*)               FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*)               FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(p.Score)           FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
            SUM(p.Score)           FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
            MAX(p.CreationDate)                                 AS LastPostDate
        FROM   Posts p
        GROUP  BY p.OwnerUserId
    ),

    badge_stats AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            MAX(b.Date)                           AS LastBadgeDate
        FROM   Badges b
        GROUP  BY b.UserId
    ),

    tag_usage AS (
        SELECT
            p.OwnerUserId                                            AS UserId,
            COUNT(DISTINCT t)                                        AS DistinctTagCount
        FROM   Posts p
        CROSS  JOIN LATERAL (
                 SELECT UNNEST(string_to_array(
                          SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2),
                          '><')) AS t
               ) AS tags
        WHERE  p.Tags IS NOT NULL
        GROUP  BY p.OwnerUserId
    ),

    recent_comments AS (
        SELECT
            c.UserId,
            COUNT(*)                         AS RecentCommentCount,
            MAX(c.CreationDate)              AS LastCommentDate
        FROM   Comments c
        WHERE  c.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP  BY c.UserId
    ),

    top_posts AS (
        SELECT
            p.OwnerUserId,
            p.Id                     AS PostId,
            p.Title,
            p.Score,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.Score DESC NULLS LAST,
                         p.CreationDate DESC
            )                        AS rn
        FROM   Posts p
        WHERE  p.PostTypeId IN (1, 2)
    ),

    top_post_per_user AS (
        SELECT *
        FROM   top_posts
        WHERE  rn = 1
    ),

    users_with_activity AS (
        SELECT
            u.Id                                      AS UserId,
            u.DisplayName,
            COALESCE(ps.QuestionCount, 0)             AS QuestionCount,
            COALESCE(ps.AnswerCount, 0)               AS AnswerCount,
            COALESCE(ps.QuestionScoreSum, 0)          AS QuestionScoreSum,
            COALESCE(ps.AnswerScoreSum, 0)            AS AnswerScoreSum,
            COALESCE(bs.GoldBadges, 0)                AS GoldBadges,
            COALESCE(bs.SilverBadges, 0)              AS SilverBadges,
            COALESCE(bs.BronzeBadges, 0)              AS BronzeBadges,
            COALESCE(tu.DistinctTagCount, 0)          AS DistinctTagCount,
            COALESCE(rc.RecentCommentCount, 0)       AS RecentCommentCount,
            GREATEST(
                COALESCE(ps.LastPostDate,   TIMESTAMP '1970-01-01'),
                COALESCE(bs.LastBadgeDate, TIMESTAMP '1970-01-01'),
                COALESCE(rc.LastCommentDate, TIMESTAMP '1970-01-01')
            )                                         AS LastActivity,
            tp.Title                                 AS TopPostTitle,
            tp.Score                                 AS TopPostScore
        FROM   usr u
        LEFT   JOIN post_stats      ps  ON ps.UserId = u.Id
        LEFT   JOIN badge_stats     bs  ON bs.UserId = u.Id
        LEFT   JOIN tag_usage       tu  ON tu.UserId = u.Id
        LEFT   JOIN recent_comments rc  ON rc.UserId = u.Id
        LEFT   JOIN top_post_per_user tp ON tp.OwnerUserId = u.Id
    )

SELECT *
FROM   users_with_activity
WHERE  (GoldBadges > 0 OR SilverBadges > 0)
   AND (DistinctTagCount >= 5 OR RecentCommentCount >= 10)
   AND (QuestionScoreSum + AnswerScoreSum) > 0
ORDER  BY (GoldBadges * 3 + SilverBadges * 2 + BronzeBadges) DESC,
          LastActivity DESC
LIMIT  100

UNION ALL

SELECT
    u.Id                                 AS UserId,
    u.DisplayName,
    0                                    AS QuestionCount,
    0                                    AS AnswerCount,
    0                                    AS QuestionScoreSum,
    0                                    AS AnswerScoreSum,
    0                                    AS GoldBadges,
    0                                    AS SilverBadges,
    0                                    AS BronzeBadges,
    0                                    AS DistinctTagCount,
    0                                    AS RecentCommentCount,
    u.CreationDate                       AS LastActivity,
    NULL::varchar                        AS TopPostTitle,
    NULL::int                            AS TopPostScore
FROM   Users u
WHERE  NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)
   AND NOT EXISTS (SELECT 1 FROM Posts p  WHERE p.OwnerUserId = u.Id)
ORDER  BY LastActivity DESC
LIMIT  50;
