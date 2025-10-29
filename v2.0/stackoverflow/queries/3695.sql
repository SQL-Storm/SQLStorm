-- {"query": "3695.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1581}
WITH recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags
    FROM Posts p
    WHERE p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
user_badge_stats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze
    FROM Badges b
    GROUP BY b.UserId
),
tag_usage AS (
    SELECT
        u.Id                              AS user_id,
        t.TagName,
        COUNT(*)                          AS tag_cnt
    FROM Users u
    JOIN LATERAL (
        SELECT
            TRIM(BOTH '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS raw_tag
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
    ) lt ON TRUE
    JOIN Tags t ON t.TagName = lt.raw_tag
    GROUP BY u.Id, t.TagName
),
top_tags AS (
    SELECT
        user_id,
        TagName,
        tag_cnt,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_cnt DESC, TagName) AS rn
    FROM tag_usage
),
top_tags_agg AS (
    SELECT
        user_id,
        all_tags_ordered,
        CASE
            WHEN all_tags_ordered IS NULL THEN NULL
            ELSE
              -- Count commas by length trick: num_commas = length - length(replace(..., ',' , ''))
              CASE WHEN (CHAR_LENGTH(all_tags_ordered) - CHAR_LENGTH(REPLACE(all_tags_ordered, ',', ''))) < 5
                   THEN all_tags_ordered
                   ELSE SUBSTRING(
                          all_tags_ordered FROM 1 FOR (
                            COALESCE(
                              NULLIF(
                                -- find position of 5th comma: use similar approach by iterating positions
                                ( 
                                  NULLIF(
                                    POSITION(',' IN all_tags_ordered), 0
                                  )
                                ), 0
                              ),
                              CHAR_LENGTH(all_tags_ordered)
                            )
                          )
                        )
              END
        END AS top_5_tags
    FROM (
        SELECT
            user_id,
            STRING_AGG(TagName, ',' ORDER BY tag_cnt DESC, TagName) AS all_tags_ordered
        FROM tag_usage
        GROUP BY user_id
    ) t
),
user_activity AS (
    SELECT
        u.Id                                   AS user_id,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS questions_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answers_cnt,
        AVG(p.Score)                            AS avg_score,
        MAX(p.LastActivityDate)                 AS last_activity,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS net_votes
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v          ON v.PostId = p.Id
    GROUP BY u.Id
)
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubs.gold,   0)      AS gold_badges,
    COALESCE(ubs.silver, 0)      AS silver_badges,
    COALESCE(ubs.bronze, 0)      AS bronze_badges,
    ua.questions_cnt,
    ua.answers_cnt,
    ua.avg_score,
    ua.net_votes,
    ua.last_activity,
    tta.top_5_tags,
    CASE
        WHEN u.Reputation >= 20000 THEN 'Legendary'
        WHEN u.Reputation >= 10000 THEN 'Trusted'
        WHEN u.Reputation >= 2000  THEN 'Experienced'
        ELSE 'Newbie'
    END                         AS reputation_tier,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
FROM Users u
LEFT JOIN user_badge_stats ubs ON ubs.UserId = u.Id
LEFT JOIN user_activity   ua  ON ua.user_id = u.Id
LEFT JOIN top_tags_agg    tta ON tta.user_id = u.Id
WHERE u.CreationDate < CAST('2024-10-01' AS date) - INTERVAL '1 year'
  AND ua.questions_cnt > 10
ORDER BY rep_rank
FETCH FIRST 100 ROWS ONLY;