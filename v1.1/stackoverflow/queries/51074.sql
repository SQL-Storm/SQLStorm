WITH popular_tags AS (
    SELECT t.TagName,
           COUNT(pt.Id) AS usage_count
    FROM Tags t
    JOIN Posts pt ON POSITION('<' || t.TagName || '>' IN pt.Tags) > 0
    WHERE pt.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(pt.Id) > 1000
),
user_activity AS (
    SELECT u.Id AS user_id,
           COUNT(p.Id) AS post_count,
           AVG(p.Score) AS avg_score,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS total_answers
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id
    HAVING COUNT(p.Id) >= 10
),
question_stats AS (
    SELECT p.Id AS question_id,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           p.Body,
           p.OwnerUserId,
           p.PostTypeId,
           COALESCE(v.up_votes, 0) AS up_votes,
           COALESCE(v.down_votes, 0) AS down_votes,
           CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
           ac.accepted_score,
           p.AcceptedAnswerId
    FROM Posts p
    LEFT JOIN (
        SELECT PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT ParentId,
               AVG(Score) AS accepted_score
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) ac ON p.Id = ac.ParentId
    WHERE p.PostTypeId = 1
      AND p.Score > 0
)
SELECT 
    qs.Title,
    qs.CreationDate,
    qs.Score AS question_score,
    qs.ViewCount,
    qs.AnswerCount,
    qs.accepted_score,
    qs.up_votes,
    qs.down_votes,
    qs.is_closed,
    pt.Name AS post_type,
    u.DisplayName AS author_name,
    ua.post_count AS author_total_posts,
    ua.avg_score AS author_avg_score,
    ua.total_answers AS author_total_answers,
    (
        SELECT ARRAY_AGG(DISTINCT t.TagName)
        FROM popular_tags t
        WHERE POSITION('<' || t.TagName || '>' IN qs.Body) > 0
    ) AS tags,
    COALESCE(c.comment_count, 0) AS recent_comments,
    COALESCE(vh.history_count, 0) AS edit_history_count,
    COALESCE(pl.link_count, 0) AS external_links,
    b.badge_count,
    ROW_NUMBER() OVER (
        PARTITION BY EXTRACT(YEAR FROM qs.CreationDate)
        ORDER BY (qs.up_votes + qs.ViewCount * 0.1 + qs.AnswerCount * 5) DESC
    ) AS yearly_rank
FROM question_stats qs
JOIN PostTypes pt ON qs.PostTypeId = pt.Id
JOIN Users u ON qs.OwnerUserId = u.Id
JOIN user_activity ua ON u.Id = ua.user_id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS comment_count
    FROM Comments
    WHERE CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY PostId
) c ON qs.question_id = c.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS history_count
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
) vh ON qs.question_id = vh.PostId
LEFT JOIN (
    SELECT PostId, COUNT(DISTINCT RelatedPostId) AS link_count
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
) pl ON qs.question_id = pl.PostId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS badge_count
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
) b ON u.Id = b.UserId
WHERE qs.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
  AND POSITION('[sql]' IN LOWER(qs.Body)) > 0
ORDER BY yearly_rank ASC
LIMIT 100;