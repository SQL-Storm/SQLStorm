WITH
user_base AS (
    SELECT
        u.Id                     AS user_id,
        u.DisplayName            AS display_name,
        u.Reputation,
        u.CreationDate           AS user_created,
        u.LastAccessDate         AS last_access,
        u.Views                  AS profile_views,
        u.UpVotes                AS up_votes_given,
        u.DownVotes              AS down_votes_given,
        COALESCE(u.AboutMe, '')  AS about_me
    FROM Users u
),

user_posts AS (
    SELECT
        p.OwnerUserId                     AS user_id,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_cnt,
        COUNT(CASE WHEN p.PostTypeId = 3 THEN 1 END) AS wiki_cnt,
        SUM(p.Score)                     AS total_score,
        AVG(p.Score)                     AS avg_score,
        MAX(p.CreationDate)              AS latest_post,
        MIN(p.CreationDate)              AS earliest_post
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

user_tags AS (
    SELECT
        p.OwnerUserId                     AS user_id,
        COUNT(DISTINCT tag) AS distinct_tag_cnt,
        ARRAY_AGG(DISTINCT tag) AS top_tags_sample_full
    FROM Posts p,
    LATERAL (
      SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))) AS tag
    ) t
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

user_badges AS (
    SELECT
        b.UserId                         AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_based_cnt,
        NULL AS gold_badges,
        NULL AS silver_badges,
        NULL AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),

user_votes AS (
    SELECT
        p.OwnerUserId                     AS user_id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_received,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_received,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favourite_received,
        COUNT(v.Id)                       AS total_votes_received
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

user_closes AS (
    SELECT
        ph.UserId                         AS user_id,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS total_closes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1 ELSE 0 END) AS dup_closes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '102' THEN 1 ELSE 0 END) AS off_topic_closes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '103' THEN 1 ELSE 0 END) AS unclear_closes,
        NULL AS close_reason_json
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId
),

user_links AS (
    SELECT
        p.OwnerUserId                     AS user_id,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_out_cnt,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_out_cnt,
        SUM(CASE WHEN pl.LinkTypeId = 1
                 AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = p.OwnerUserId)
             THEN 1 ELSE 0 END)                                     AS linked_in_cnt,
        SUM(CASE WHEN pl.LinkTypeId = 3
                 AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = p.OwnerUserId)
             THEN 1 ELSE 0 END)                                     AS duplicate_in_cnt
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

user_aggregated AS (
    SELECT
        ub.user_id,
        ub.display_name,
        ub.reputation,
        ub.user_created,
        ub.last_access,
        ub.profile_views,
        ub.up_votes_given,
        ub.down_votes_given,
        up.question_cnt,
        up.answer_cnt,
        up.wiki_cnt,
        up.total_score,
        up.avg_score,
        up.latest_post,
        up.earliest_post,
        ut.distinct_tag_cnt,
        ut.top_tags_sample_full AS top_tags_sample,
        ubg.gold_cnt,
        ubg.silver_cnt,
        ubg.bronze_cnt,
        ubg.tag_based_cnt,
        ubg.gold_badges,
        ubg.silver_badges,
        ubg.bronze_badges,
        uv.upvote_received,
        uv.downvote_received,
        uv.favourite_received,
        uv.total_votes_received,
        uc.total_closes,
        uc.dup_closes,
        uc.off_topic_closes,
        uc.unclear_closes,
        uc.close_reason_json,
        ul.linked_out_cnt,
        ul.duplicate_out_cnt,
        ul.linked_in_cnt,
        ul.duplicate_in_cnt,
        (0.4 * COALESCE(ub.reputation,0)
         + 0.3 * COALESCE(up.total_score,0)
         + 0.2 * COALESCE(uv.upvote_received,0)
         + 0.1 * COALESCE(ubg.gold_cnt,0) * 100
        ) AS activity_score
    FROM user_base ub
    LEFT JOIN user_posts up      ON up.user_id = ub.user_id
    LEFT JOIN user_tags ut       ON ut.user_id = ub.user_id
    LEFT JOIN user_badges ubg    ON ubg.user_id = ub.user_id
    LEFT JOIN user_votes uv      ON uv.user_id = ub.user_id
    LEFT JOIN user_closes uc     ON uc.user_id = ub.user_id
    LEFT JOIN user_links ul      ON ul.user_id = ub.user_id
)

SELECT
    ua.user_id,
    ua.display_name,
    ua.reputation,
    ua.question_cnt,
    ua.answer_cnt,
    ua.wiki_cnt,
    ua.total_score,
    ua.avg_score,
    ua.distinct_tag_cnt,
    ua.top_tags_sample,
    ua.gold_cnt,
    ua.silver_cnt,
    ua.bronze_cnt,
    ua.tag_based_cnt,
    ua.upvote_received,
    ua.downvote_received,
    ua.favourite_received,
    ua.total_votes_received,
    ua.total_closes,
    ua.dup_closes,
    ua.off_topic_closes,
    ua.unclear_closes,
    ua.close_reason_json,
    ua.linked_out_cnt,
    ua.duplicate_out_cnt,
    ua.linked_in_cnt,
    ua.duplicate_in_cnt,
    ua.activity_score,
    ROW_NUMBER() OVER (ORDER BY ua.activity_score DESC) AS activity_rank
FROM user_aggregated ua
ORDER BY ua.activity_score DESC
LIMIT 100;