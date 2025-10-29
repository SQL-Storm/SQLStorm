WITH
usr_recent AS (
    SELECT u.Id                           AS user_id,
           u.DisplayName,
           MAX(p.CreationDate)           AS last_post_dt,
           MAX(c.CreationDate)           AS last_comment_dt,
           GREATEST(
               COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01'),
               COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')
           )                             AS last_activity_dt
    FROM   Users u
    LEFT   JOIN Posts p      ON p.OwnerUserId = u.Id
                               AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '90' DAY
    LEFT   JOIN Comments c   ON c.UserId = u.Id
                               AND c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '90' DAY
    GROUP  BY u.Id, u.DisplayName
),

usr_votes AS (
    SELECT u.Id                                               AS user_id,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  AS up_votes_given,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)  AS down_votes_given,
           COALESCE(SUM(CASE WHEN p.OwnerUserId = u.Id
                             AND v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS up_votes_received,
           COALESCE(SUM(CASE WHEN p.OwnerUserId = u.Id
                             AND v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS down_votes_received
    FROM   Users u
    LEFT   JOIN Votes v        ON v.UserId = u.Id
    LEFT   JOIN Posts p        ON p.Id = v.PostId
    GROUP  BY u.Id
),

usr_badges AS (
    SELECT b.UserId                                          AS user_id,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END)           AS gold_cnt,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END)           AS silver_cnt,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END)           AS bronze_cnt,
           COUNT(*)                                          AS total_cnt
    FROM   Badges b
    GROUP  BY b.UserId
),

usr_top_tags AS (
    SELECT u.Id                                            AS user_id,
           t.tag,
           t.cnt,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY t.cnt DESC) AS rn
    FROM   Users u
    JOIN   LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
        FROM   Posts p
        WHERE  p.OwnerUserId = u.Id
               AND p.PostTypeId = 2
    ) tags ON TRUE
    JOIN   LATERAL (
        SELECT tags.tag AS tag, COUNT(*) AS cnt
        FROM   Posts p2
        WHERE  p2.PostTypeId = 2
               AND p2.OwnerUserId = u.Id
               AND p2.Tags ILIKE '%'||tags.tag||'%'
        GROUP  BY tags.tag
    ) t ON t.tag = tags.tag
    GROUP  BY u.Id, t.tag, t.cnt
),

closed_dupes AS (
    SELECT p.Id            AS post_id,
           p.Title,
           p.CreationDate,
           ph.Comment      AS close_reason,
           pl.RelatedPostId AS duplicate_of
    FROM   Posts p
    JOIN   PostHistory ph ON ph.PostId = p.Id
                           AND ph.PostHistoryTypeId = 10
    JOIN   PostLinks pl   ON pl.PostId = p.Id
                           AND pl.LinkTypeId = 3
    WHERE  p.PostTypeId = 1
    UNION ALL
    SELECT p.Id, p.Title, p.CreationDate,
           CAST('No close reason recorded' AS text),
           CAST(NULL AS integer)
    FROM   Posts p
    LEFT   JOIN PostHistory ph ON ph.PostId = p.Id
                                AND ph.PostHistoryTypeId = 10
    LEFT   JOIN PostLinks pl   ON pl.PostId = p.Id
                                AND pl.LinkTypeId = 3
    WHERE  p.PostTypeId = 1
      AND  ph.Id IS NULL
      AND  pl.Id IS NULL
)

SELECT
    u.Id                                    AS user_id,
    u.DisplayName,
    COALESCE(ur.last_activity_dt, u.CreationDate)                AS last_activity,
    uv.up_votes_given,
    uv.down_votes_given,
    uv.up_votes_received,
    uv.down_votes_received,
    COALESCE(ub.gold_cnt,0)    AS gold_badges,
    COALESCE(ub.silver_cnt,0)  AS silver_badges,
    COALESCE(ub.bronze_cnt,0)  AS bronze_badges,
    COALESCE(ub.total_cnt,0)   AS total_badges,
    u.Reputation
      + (CASE WHEN ur.last_post_dt IS NOT NULL THEN 10 ELSE 0 END)
      + (CASE WHEN ur.last_comment_dt IS NOT NULL THEN 5 ELSE 0 END)
      - (COALESCE(uv.down_votes_received,0) * 2)                               AS adjusted_rep,
    COALESCE(
        STRING_AGG(tt.tag, ', ') FILTER (WHERE tt.rn <= 3),
        'No tags'
    )                                           AS top_tags,
    CASE
        WHEN COALESCE(ub.gold_cnt,0) > 0
         AND EXISTS (SELECT 1 FROM closed_dupes cd WHERE cd.post_id IN (
                        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id))
        THEN 'VIP'
        ELSE NULL
    END                                          AS special_flag
FROM   Users u
LEFT   JOIN usr_recent ur      ON ur.user_id = u.Id
LEFT   JOIN usr_votes uv       ON uv.user_id = u.Id
LEFT   JOIN usr_badges ub      ON ub.user_id = u.Id
LEFT   JOIN usr_top_tags tt    ON tt.user_id = u.Id
GROUP  BY u.Id, u.DisplayName, u.Reputation, u.CreationDate,
          ur.last_activity_dt, ur.last_post_dt, ur.last_comment_dt,
          uv.up_votes_given, uv.down_votes_given,
          uv.up_votes_received, uv.down_votes_received,
          ub.gold_cnt, ub.silver_cnt, ub.bronze_cnt, ub.total_cnt,
          tt.tag, tt.cnt, tt.rn
ORDER  BY adjusted_rep DESC
LIMIT  100;