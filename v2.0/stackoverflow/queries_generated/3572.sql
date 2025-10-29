-- {"query": "3572.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2329} 

/*  Complex benchmarking query using the StackOverflow schema  */
WITH
    /* users with badge breakdown */
    top_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(b.Id) FILTER (WHERE b.Class = 1)               AS gold_badges,
            COUNT(b.Id) FILTER (WHERE b.Class = 2)               AS silver_badges,
            COUNT(b.Id) FILTER (WHERE b.Class = 3)               AS bronze_badges,
            SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END)      AS tag_badges,
            u.CreationDate
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
        HAVING COUNT(b.Id) > 0
    ),

    /* recent activity per user */
    recent_activity AS (
        SELECT
            p.OwnerUserId                              AS user_id,
            MAX(p.LastActivityDate)                    AS last_activity,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)   AS questions_asked,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)   AS answers_given,
            SUM(p.Score)                               AS total_score
        FROM Posts p
        WHERE p.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
        GROUP BY p.OwnerUserId
    ),

    /* tag usage statistics */
    tag_usage AS (
        SELECT
            t.TagName,
            t.Count                                                  AS tag_total,
            COALESCE(SUM(p.ViewCount),0)                              AS tag_views,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC)                AS tag_rank
        FROM Tags t
        LEFT JOIN Posts p
          ON p.Tags IS NOT NULL
         AND (','||REPLACE(REPLACE(p.Tags,'<',''),'>','')||',') LIKE '%,'||t.TagName||',%'
        GROUP BY t.TagName, t.Count
    ),

    /* most recent close reason per post */
    close_reasons AS (
        SELECT
            ph.PostId,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS close_reason_id,
            MIN(ph.CreationDate)                                           AS closed_on
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ),

    /* latest post per user (correlated sub‑query) */
    latest_post AS (
        SELECT
            p.OwnerUserId,
            p.Id                                    AS post_id,
            p.CreationDate,
            p.Tags
        FROM Posts p
        WHERE p.Id = (
            SELECT p2.Id
            FROM Posts p2
            WHERE p2.OwnerUserId = p.OwnerUserId
            ORDER BY p2.CreationDate DESC
            LIMIT 1
        )
    )

SELECT
    tu.Id                                    AS user_id,
    tu.DisplayName,
    tu.Reputation,
    tu.gold_badges,
    tu.silver_badges,
    tu.bronze_badges,
    COALESCE(ra.questions_asked,0)           AS questions_asked,
    COALESCE(ra.answers_given,0)             AS answers_given,
    COALESCE(ra.total_score,0)               AS user_score,
    CASE
        WHEN tu.Reputation > 20000 THEN 'Legendary'
        WHEN tu.Reputation > 10000 THEN 'Expert'
        WHEN tu.Reputation > 2000  THEN 'Contributor'
        ELSE 'Newbie'
    END                                      AS reputation_band,
    COALESCE(ra.last_activity, tu.CreationDate) AS last_seen,
    COALESCE(cr.close_reason_id,'0')          AS last_close_reason_id,
    cr.closed_on                              AS last_closed_date,
    /* top tag for this user based on his/her posts */
    (SELECT t.TagName
       FROM latest_post lp
      INNER JOIN LATERAL regexp_split_to_table(lp.Tags, '[><]') AS tg(tag) ON true
      INNER JOIN Tags t ON t.TagName = tg.tag
      WHERE lp.OwnerUserId = tu.Id
      GROUP BY t.TagName
      ORDER BY COUNT(*) DESC
      LIMIT 1)                              AS top_user_tag,
    /* rank of the user by total score */
    RANK() OVER (ORDER BY COALESCE(ra.total_score,0) DESC) AS score_rank
FROM top_users tu
FULL OUTER JOIN recent_activity ra   ON ra.user_id = tu.Id
LEFT JOIN close_reasons cr          ON cr.PostId = (
                                            SELECT p.Id
                                            FROM Posts p
                                            WHERE p.OwnerUserId = tu.Id
                                            ORDER BY p.CreationDate DESC
                                            LIMIT 1
                                         )
WHERE (tu.gold_badges + tu.silver_badges + tu.bronze_badges) > 5
  AND (tu.Reputation IS NOT NULL OR ra.total_score IS NOT NULL)

UNION ALL

/*  Aggregated placeholder row – exercises set operator handling  */
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    'Aggregated',
    NULL, NULL,
    NULL,
    NULL,
    NULL
FROM (SELECT 1) AS dummy

ORDER BY
    reputation_band NULLS LAST,
    score_rank ASC
LIMIT 100;
