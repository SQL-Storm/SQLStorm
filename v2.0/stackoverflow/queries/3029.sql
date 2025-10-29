-- {"query": "3029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1506}
WITH recent_posts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        p.CommunityOwnedDate
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '90 days')
),
user_post_stats AS (
    SELECT
        u.Id                                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN 1 END)       AS QuestionCount90d,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN 1 END)       AS AnswerCount90d,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.Score ELSE 0 END) AS QuestionScoreSum90d,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.Score ELSE 0 END) AS AnswerScoreSum90d,
        COUNT(DISTINCT rp.Tags)                        AS DistinctTagCount,
        COALESCE(b.badge_cnt, 0)                       AS BadgeCount,
        COALESCE(v.vote_up_cnt, 0)                     AS UpVoteCount,
        COALESCE(v.vote_down_cnt, 0)                   AS DownVoteCount
    FROM Users u
    LEFT JOIN recent_posts rp
        ON rp.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS badge_cnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT v.UserId,
               COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS vote_up_cnt,
               COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS vote_down_cnt
        FROM Votes v
        GROUP BY v.UserId
    ) v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.badge_cnt, v.vote_up_cnt, v.vote_down_cnt
),
user_tag_agg AS (
    SELECT
        ups.UserId,
        split_tags.tag,
        COUNT(*)                                     AS TagPostCount,
        AVG(rp.Score)                                 AS AvgScorePerTag,
        ROW_NUMBER() OVER (PARTITION BY ups.UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM user_post_stats ups
    JOIN recent_posts rp
        ON rp.OwnerUserId = ups.UserId
    JOIN (
        -- split tags like '<tag1><tag2>' into rows: remove leading/trailing '<' and '>' and split on '><'
        SELECT rp_inner.Id AS PostId, TRIM(BOTH ' ' FROM REPLACE(REPLACE(val, '<', ''), '>', '')) AS tag
        FROM recent_posts rp_inner,
             LATERAL (
                 SELECT unnest(string_to_array(rp_inner.Tags, '><')) AS val
             ) s(val)
        WHERE rp_inner.Tags IS NOT NULL
    ) split_tags ON split_tags.PostId = rp.Id
    GROUP BY ups.UserId, split_tags.tag
),
top_users_by_activity AS (
    SELECT
        ups.*,
        ROW_NUMBER() OVER (ORDER BY (ups.QuestionCount90d + ups.AnswerCount90d) DESC) AS ActivityRank
    FROM user_post_stats ups
    WHERE ups.Reputation > 1000
),
badge_veterans AS (
    SELECT
        UserId,
        BadgeCount,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC) AS BadgeRank
    FROM user_post_stats
    WHERE BadgeCount >= 50
),
combined_ranks AS (
    SELECT UserId, ActivityRank, CAST(NULL AS INTEGER) AS BadgeRank
    FROM top_users_by_activity
    UNION ALL
    SELECT UserId, CAST(NULL AS INTEGER) AS ActivityRank, BadgeRank
    FROM badge_veterans
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount90d,
    u.AnswerCount90d,
    u.QuestionScoreSum90d,
    u.AnswerScoreSum90d,
    u.DistinctTagCount,
    u.BadgeCount,
    u.UpVoteCount,
    u.DownVoteCount,
    cr.ActivityRank,
    cr.BadgeRank,
    COALESCE(tagg.tag, '(no tag)')                      AS TopTag,
    COALESCE(tagg.TagPostCount, 0)                      AS TopTagPostCount,
    COALESCE(ROUND(tagg.AvgScorePerTag, 2), 0)          AS TopTagAvgScore
FROM user_post_stats u
LEFT JOIN combined_ranks cr
    ON cr.UserId = u.UserId
LEFT JOIN LATERAL (
    SELECT tag, TagPostCount, AvgScorePerTag
    FROM user_tag_agg uta
    WHERE uta.UserId = u.UserId
      AND uta.TagRank = 1
) tagg ON TRUE
WHERE (cr.ActivityRank IS NOT NULL AND cr.ActivityRank <= 20)
   OR (cr.BadgeRank IS NOT NULL AND cr.BadgeRank <= 20)
ORDER BY
    COALESCE(cr.ActivityRank, 9999),
    COALESCE(cr.BadgeRank, 9999),
    u.Reputation DESC;