WITH tag_questions AS (
    SELECT 
        p.Id AS post_id,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        -- replace PostgreSQL-specific string_to_array/unnest with standard-ish split; use regexp_split_to_table alternative for dialects that support it,
        -- fallback: split tags by removing leading/trailing <> and splitting on '><' using a generic SPLIT_PART in a numbers approach is complex;
        -- Here use regexp_split_to_table equivalent name REGEXP_SPLIT_TO_TABLE for compatibility; if not available, replace with your dialect's string-split table function.
        regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
user_tag_stats AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        t.tag,
        COUNT(t.post_id) AS question_count,
        SUM(t.Score) AS total_score,
        AVG(t.Score) AS avg_score,
        SUM(t.ViewCount) AS total_views,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS edit_count,
        COUNT(DISTINCT c.Id) AS comment_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvote_count,
        COUNT(DISTINCT b.Id) AS badge_count,
        RANK() OVER (PARTITION BY t.tag ORDER BY u.Reputation DESC) AS reputation_rank
    FROM Users u
    JOIN tag_questions t ON u.Id = t.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = t.post_id AND ph.UserId = u.Id
    LEFT JOIN Comments c ON c.PostId = t.post_id AND c.UserId = u.Id
    LEFT JOIN Votes v ON v.PostId = t.post_id AND v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.tag
),
top_tags AS (
    SELECT tag
    FROM tag_questions
    GROUP BY tag
    ORDER BY COUNT(*) DESC
    LIMIT 20
)
SELECT 
    uts.user_id,
    uts.DisplayName,
    uts.Reputation,
    uts.tag,
    uts.question_count,
    uts.total_score,
    uts.avg_score,
    uts.total_views,
    uts.edit_count,
    uts.comment_count,
    uts.upvote_count,
    uts.downvote_count,
    uts.badge_count,
    uts.reputation_rank,
    CASE 
        WHEN uts.question_count > 10 AND uts.total_score > 100 THEN 'Prolific'
        WHEN uts.badge_count > 5 THEN 'Badged'
        ELSE 'Active'
    END AS user_category
FROM user_tag_stats uts
JOIN top_tags tt ON uts.tag = tt.tag
WHERE uts.question_count > 1
ORDER BY uts.tag, uts.reputation_rank, uts.total_score DESC;