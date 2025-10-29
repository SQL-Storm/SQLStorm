WITH
UserReputation AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn,
           COUNT(*) OVER () AS total_users
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
UserBadgeCounts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 5
                    WHEN b.Class = 2 THEN 3
                    ELSE 1 END) AS badge_score,
           COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS tag_badge_cnt,
           COUNT(CASE WHEN b.TagBased = FALSE THEN 1 END) AS named_badge_cnt
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_cnt,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_cnt,
           COALESCE(SUM(p.Score),0) AS total_score,
           MAX(p.CreationDate) AS last_post_date
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteStats AS (
    SELECT v.UserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS up_votes_given,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS down_votes_given,
           COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites_given
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
TopTags AS (
    SELECT t.TagName,
           t.Count AS tag_use_cnt,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
      AND t.IsModeratorOnly = FALSE
      AND t.IsRequired = FALSE
),
RecentClosedQuestions AS (
    SELECT p.Id,
           p.Title,
           p.Tags,
           ph.CreationDate AS closed_date,
           CAST(ph.Comment AS INTEGER) AS close_reason_id,
           ROW_NUMBER() OVER (PARTITION BY CAST(ph.Comment AS INTEGER) ORDER BY ph.CreationDate DESC) AS rn_per_reason,
           ph.Comment
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
),
UserQuestionTagMatrix AS (
    SELECT ua.Id AS UserId,
           t.tag AS Tag,
           COUNT(*) AS q_per_tag
    FROM Posts p
    JOIN UserReputation ua ON ua.Id = p.OwnerUserId,
         UNNEST(string_to_array(p.Tags, '><')) AS t(tag)
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY ua.Id, t.tag
)
SELECT
    ur.Id AS UserId,
    ur.DisplayName,
    ur.Reputation,
    ub.badge_score,
    ub.tag_badge_cnt,
    ub.named_badge_cnt,
    ua.question_cnt,
    ua.answer_cnt,
    ua.total_score,
    uv.up_votes_given,
    uv.down_votes_given,
    uv.favorites_given,
    CASE
        WHEN ua.total_score >= 0 THEN ua.total_score
        ELSE NULL
    END AS net_positive_score,
    COALESCE(ua.last_post_date, ur.CreationDate) AS last_activity,
    ROW_NUMBER() OVER (ORDER BY (ur.Reputation * 0.5) + (COALESCE(ub.badge_score,0) * 2) + (COALESCE(ua.total_score,0) * 1.5) DESC) AS composite_rank,
    (SELECT tt.TagName
     FROM UserQuestionTagMatrix uq
     JOIN TopTags tt ON tt.TagName = uq.Tag
     WHERE uq.UserId = ur.Id
     ORDER BY uq.q_per_tag DESC, tt.tag_use_cnt DESC
     FETCH FIRST 1 ROW ONLY) AS top_user_tag,
    (SELECT COUNT(*)
     FROM RecentClosedQuestions rcq
     WHERE rcq.Id IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ur.Id)
       AND rcq.rn_per_reason = 1) AS distinct_close_reason_cnt
FROM UserReputation ur
LEFT JOIN UserBadgeCounts ub ON ub.UserId = ur.Id
LEFT JOIN UserActivity ua ON ua.UserId = ur.Id
LEFT JOIN UserVoteStats uv ON uv.UserId = ur.Id
WHERE ur.rn <= 1000

UNION ALL

SELECT
    NULL AS UserId,
    'Aggregate Snapshot' AS DisplayName,
    NULL AS Reputation,
    SUM(ub.badge_score) AS badge_score,
    SUM(ub.tag_badge_cnt) AS tag_badge_cnt,
    SUM(ub.named_badge_cnt) AS named_badge_cnt,
    SUM(ua.question_cnt) AS question_cnt,
    SUM(ua.answer_cnt) AS answer_cnt,
    SUM(ua.total_score) AS total_score,
    SUM(uv.up_votes_given) AS up_votes_given,
    SUM(uv.down_votes_given) AS down_votes_given,
    SUM(uv.favorites_given) AS favorites_given,
    NULL AS net_positive_score,
    MAX(ua.last_post_date) AS last_activity,
    NULL AS composite_rank,
    NULL AS top_user_tag,
    COUNT(DISTINCT CAST(rcq.Comment AS INTEGER)) AS distinct_close_reason_cnt
FROM UserBadgeCounts ub
JOIN UserActivity ua ON ua.UserId = ub.UserId
JOIN UserVoteStats uv ON uv.UserId = ub.UserId
JOIN RecentClosedQuestions rcq ON rcq.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = ub.UserId)
WHERE ub.UserId IS NOT NULL
GROUP BY -- group by all non-aggregated selected columns that are not constants
    'Aggregate Snapshot',
    NULL;