SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(answer_stats.total_answer_score, 0) AS TotalAnswerScore,
    COALESCE(question_stats.total_question_score, 0) AS TotalQuestionScore,
    badge_counts.gold_badges,
    badge_counts.silver_badges,
    badge_counts.bronze_badges,
    post_activity.comment_count,
    post_activity.vote_count
FROM Users u
LEFT JOIN (
    SELECT 
        p.OwnerUserId,
        SUM(p.Score) AS total_answer_score
    FROM Posts p
    WHERE p.PostTypeId = 2 
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
) answer_stats ON u.Id = answer_stats.OwnerUserId
LEFT JOIN (
    SELECT 
        p.OwnerUserId,
        SUM(p.Score) AS total_question_score
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
) question_stats ON u.Id = question_stats.OwnerUserId
LEFT JOIN (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY b.UserId
) badge_counts ON u.Id = badge_counts.UserId
LEFT JOIN (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS comment_count
    FROM Comments c
    WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY c.UserId
) comment_activity ON u.Id = comment_activity.UserId
LEFT JOIN (
    SELECT 
        p.OwnerUserId,
        COALESCE(activity.comment_count, 0) AS comment_count,
        COALESCE(vote_activity.vote_count, 0) AS vote_count
    FROM Posts p
    LEFT JOIN (
        SELECT 
            c.PostId,
            COUNT(c.Id) AS comment_count
        FROM Comments c
        WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
        GROUP BY c.PostId
    ) activity ON p.Id = activity.PostId
    LEFT JOIN (
        SELECT 
            v.PostId,
            COUNT(v.Id) AS vote_count
        FROM Votes v
        WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
        GROUP BY v.PostId
    ) vote_activity ON p.Id = vote_activity.PostId
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId, activity.comment_count, vote_activity.vote_count
) post_activity ON u.Id = post_activity.OwnerUserId
WHERE u.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
  AND u.Reputation > 1000
ORDER BY (COALESCE(answer_stats.total_answer_score, 0) + COALESCE(question_stats.total_question_score, 0) + COALESCE(badge_counts.gold_badges,0) * 10 + COALESCE(badge_counts.silver_badges,0) * 5 + COALESCE(badge_counts.bronze_badges,0) * 1 + COALESCE(post_activity.comment_count,0) + COALESCE(post_activity.vote_count,0)) DESC
LIMIT 100;