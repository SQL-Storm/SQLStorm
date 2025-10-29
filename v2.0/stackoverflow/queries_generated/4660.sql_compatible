WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.ClosedDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS rn_by_type_score,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_for_post,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS is_closed_flag
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS body_edit_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS last_body_edit_date,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 END) AS tags_edit_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate ELSE NULL END) AS last_tags_edit_date,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 END) AS moderation_event_count
    FROM PostHistory ph
    WHERE ph.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
    GROUP BY ph.PostId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS posts_authored,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_asked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_given,
        COUNT(DISTINCT b.Id) AS badges_earned,
        SUM(p.Score) AS total_score_on_posts,
        AVG(CAST(u.Reputation AS DOUBLE PRECISION)) OVER () AS overall_avg_reputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
    GROUP BY u.Id, u.Reputation
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeId,
    CASE rp.PostTypeId
        WHEN 1 THEN 'Question'
        WHEN 2 THEN 'Answer'
        WHEN 3 THEN 'Wiki'
        WHEN 4 THEN 'TagWikiExcerpt'
        WHEN 5 THEN 'TagWiki'
        WHEN 6 THEN 'ModeratorNomination'
        WHEN 7 THEN 'WikiPlaceholder'
        WHEN 8 THEN 'PrivilegeWiki'
        ELSE 'Unknown'
    END AS PostTypeName,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ClosedDate,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.rn_by_type_score,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    rp.is_closed_flag,
    phs.body_edit_count,
    phs.last_body_edit_date,
    phs.tags_edit_count,
    phs.last_tags_edit_date,
    phs.moderation_event_count,
    uas.posts_authored,
    uas.questions_asked,
    uas.answers_given,
    uas.badges_earned,
    uas.total_score_on_posts,
    uas.overall_avg_reputation,
    COALESCE(rp.OwnerReputation, 0) * rp.Score AS reputation_score_interaction,
    CHAR_LENGTH(rp.Title) AS title_length,
    CAST(EXTRACT(EPOCH FROM (rp.LastActivityDate - rp.CreationDate)) / 86400 AS INTEGER) AS days_since_creation_to_last_activity,
    CASE
        WHEN rp.FavoriteCount > (rp.AnswerCount * 2) THEN 'Highly Favorited'
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'High Engagement'
        ELSE 'Standard'
    END AS post_engagement_category,
    CASE
        WHEN rp.OwnerReputation > 100000 THEN 'Expert'
        WHEN rp.OwnerReputation BETWEEN 10000 AND 100000 THEN 'Experienced'
        ELSE 'Beginner'
    END AS owner_experience_level
FROM RankedPosts rp
FULL OUTER JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserActivitySummary uas ON rp.OwnerUserId = uas.UserId
WHERE rp.rn_by_type_score <= 100
GROUP BY
    rp.PostId,
    rp.Title,
    rp.PostTypeId,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ClosedDate,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.rn_by_type_score,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    rp.is_closed_flag,
    phs.body_edit_count,
    phs.last_body_edit_date,
    phs.tags_edit_count,
    phs.last_tags_edit_date,
    phs.moderation_event_count,
    uas.posts_authored,
    uas.questions_asked,
    uas.answers_given,
    uas.badges_earned,
    uas.total_score_on_posts,
    uas.overall_avg_reputation
ORDER BY rp.PostTypeId, rp.rn_by_type_score;