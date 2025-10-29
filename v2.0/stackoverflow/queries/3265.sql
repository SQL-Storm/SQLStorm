-- {"query": "3265.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2970}
WITH
recent_user_posts AS (
    SELECT  p.OwnerUserId               AS user_id,
            p.Id                        AS post_id,
            p.CreationDate              AS post_date,
            p.Score                     AS post_score,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY p.CreationDate DESC) AS rn
    FROM    Posts p
    WHERE   p.OwnerUserId IS NOT NULL
),

top_recent_post AS (
    SELECT  user_id,
            post_id,
            post_date,
            post_score
    FROM    recent_user_posts
    WHERE   rn = 1
),

badge_stats AS (
    SELECT  b.UserId                                     AS user_id,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END)      AS gold_cnt,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END)      AS silver_cnt,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END)      AS bronze_cnt,
            COUNT(*)                                     AS total_cnt,
            STRING_AGG(DISTINCT b.Name, ', ')           AS badge_list
    FROM    Badges b
    GROUP BY b.UserId
),

post_stats AS (
    SELECT  p.OwnerUserId                              AS user_id,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)   AS q_cnt,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)   AS a_cnt,
            SUM(p.Score)                               AS score_sum,
            AVG(p.ViewCount)                           AS avg_views,
            MAX(p.FavoriteCount)                       AS max_favs
    FROM    Posts p
    WHERE   p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

vote_stats AS (
    SELECT  v.PostId                                   AS post_id,
            COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END)   AS up_votes,
            COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END)   AS down_votes,
            COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END)   AS fav_votes
    FROM    Votes v
    GROUP BY v.PostId
),

post_tags AS (
    SELECT  tr.user_id,
            tr.post_id,
            UNNEST(
                STRING_TO_ARRAY(
                    TRIM(BOTH '<>' FROM COALESCE(p.Tags,'')),
                    '><'
                )
            )                                            AS tag
    FROM    top_recent_post tr
    LEFT JOIN Posts p ON p.Id = tr.post_id
),

tag_stats AS (
    SELECT  t.TagName                                   AS tag_name,
            COUNT(DISTINCT pt.post_id)                 AS posts_with_tag,
            SUM(p.Score)                               AS tag_score_sum,
            AVG(p.ViewCount)                           AS tag_avg_views
    FROM    Tags t
    JOIN    post_tags pt   ON pt.tag = t.TagName
    JOIN    Posts p        ON p.Id = pt.post_id
    GROUP BY t.TagName
),

user_tag_matrix AS (
    SELECT  u.Id                              AS user_id,
            u.DisplayName                     AS user_name,
            u.Reputation,
            COALESCE(bs.gold_cnt,0)           AS gold_badges,
            COALESCE(bs.silver_cnt,0)         AS silver_badges,
            COALESCE(bs.bronze_cnt,0)         AS bronze_badges,
            COALESCE(ps.q_cnt,0)              AS question_cnt,
            COALESCE(ps.a_cnt,0)              AS answer_cnt,
            COALESCE(ps.score_sum,0)          AS total_score,
            COALESCE(ps.avg_views,0)          AS avg_views,
            COALESCE(ps.max_favs,0)           AS max_favorites,
            tr.post_id                        AS recent_post_id,
            tr.post_date                      AS recent_post_date,
            tr.post_score                     AS recent_post_score,
            COALESCE(vs.up_votes,0)           AS recent_up_votes,
            COALESCE(vs.down_votes,0)         AS recent_down_votes,
            COALESCE(vs.fav_votes,0)          AS recent_fav_votes,
            bs.badge_list                     AS all_badges,
            ts.tag_name,
            ts.posts_with_tag,
            ts.tag_score_sum,
            ts.tag_avg_views,
            ROW_NUMBER() OVER (PARTITION BY u.Id
                               ORDER BY ts.tag_score_sum DESC) AS tag_rank
    FROM    Users u
    LEFT JOIN badge_stats   bs ON bs.user_id = u.Id
    LEFT JOIN post_stats    ps ON ps.user_id = u.Id
    LEFT JOIN top_recent_post tr ON tr.user_id = u.Id
    LEFT JOIN vote_stats    vs ON vs.post_id = tr.post_id
    LEFT JOIN post_tags     pt ON pt.user_id = u.Id
    LEFT JOIN tag_stats     ts ON ts.tag_name = pt.tag
),

top_user_tags AS (
    SELECT user_id,
           user_name,
           Reputation,
           gold_badges,
           silver_badges,
           bronze_badges,
           question_cnt,
           answer_cnt,
           total_score,
           avg_views,
           max_favorites,
           recent_post_id,
           recent_post_date,
           recent_post_score,
           recent_up_votes,
           recent_down_votes,
           recent_fav_votes,
           all_badges,
           tag_name,
           posts_with_tag,
           tag_score_sum,
           tag_avg_views,
           tag_rank
    FROM   user_tag_matrix
    WHERE  tag_rank <= 3
),

first_result_set AS (
    SELECT  user_id,
            user_name,
            Reputation,
            gold_badges,
            silver_badges,
            bronze_badges,
            question_cnt,
            answer_cnt,
            total_score,
            avg_views,
            max_favorites,
            recent_post_id,
            recent_post_date,
            recent_post_score,
            recent_up_votes,
            recent_down_votes,
            recent_fav_votes,
            all_badges,
            tag_name,
            posts_with_tag,
            tag_score_sum,
            tag_avg_views,
            tag_rank
    FROM    top_user_tags
    WHERE   user_id IS NOT NULL
    ORDER BY Reputation DESC, tag_rank ASC
    LIMIT   100
),

second_result_set AS (
    SELECT  u.Id               AS user_id,
            u.DisplayName      AS user_name,
            u.Reputation,
            CAST(NULL AS INTEGER)               AS gold_badges,
            CAST(NULL AS INTEGER)               AS silver_badges,
            CAST(NULL AS INTEGER)               AS bronze_badges,
            CAST(NULL AS INTEGER)               AS question_cnt,
            CAST(NULL AS INTEGER)               AS answer_cnt,
            CAST(NULL AS BIGINT)                AS total_score,
            CAST(NULL AS DOUBLE PRECISION)      AS avg_views,
            CAST(NULL AS INTEGER)               AS max_favorites,
            CAST(NULL AS INTEGER)               AS recent_post_id,
            CAST(NULL AS TIMESTAMP)             AS recent_post_date,
            CAST(NULL AS INTEGER)               AS recent_post_score,
            CAST(NULL AS INTEGER)               AS recent_up_votes,
            CAST(NULL AS INTEGER)               AS recent_down_votes,
            CAST(NULL AS INTEGER)               AS recent_fav_votes,
            CAST(NULL AS TEXT)                  AS all_badges,
            CAST(NULL AS TEXT)                  AS tag_name,
            CAST(NULL AS INTEGER)               AS posts_with_tag,
            CAST(NULL AS BIGINT)                AS tag_score_sum,
            CAST(NULL AS DOUBLE PRECISION)      AS tag_avg_views,
            CAST(NULL AS INTEGER)               AS tag_rank
    FROM    Users u
    WHERE   COALESCE(u.Reputation,0) = 0
    ORDER BY user_id
    LIMIT   10
)

SELECT * FROM first_result_set
UNION ALL
SELECT * FROM second_result_set;