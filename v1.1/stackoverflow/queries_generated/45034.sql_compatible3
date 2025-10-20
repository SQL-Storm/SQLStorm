WITH high_impact_users AS (
    SELECT Users.Id AS UserId,
           COUNT(DISTINCT Posts.Id) AS posts_count,
           AVG(Posts.Score) AS avg_post_score,
           SUM(Posts.AnswerCount) AS total_answers_received
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.PostTypeId = 1 AND Users.Reputation > 10000
    GROUP BY Users.Id
), tag_complexity AS (
    SELECT 
        tag,
        COUNT(DISTINCT p.Id) AS tag_post_count,
        AVG(p.ViewCount) AS avg_view_count,
        MAX(p.Score) AS max_tag_score
    FROM Posts p,
    LATERAL (
      SELECT TRIM(t) AS tag
      FROM (
        -- replace XML parsing for tag extraction: convert ">...<" delimited Tags like "<tag1><tag2>" into rows
        SELECT REGEXP_SPLIT_TO_TABLE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><') AS t
      ) s
    ) tags
    WHERE p.PostTypeId = 1
    GROUP BY tag
)
SELECT 
    u.DisplayName,
    hiu.posts_count,
    hiu.avg_post_score,
    hiu.total_answers_received,
    tc.tag,
    tc.tag_post_count,
    tc.avg_view_count
FROM high_impact_users hiu
JOIN Users u ON hiu.UserId = u.Id
JOIN tag_complexity tc ON 
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
          AND p.Tags LIKE '%' || tc.tag || '%'
    )
GROUP BY u.DisplayName,
         hiu.posts_count,
         hiu.avg_post_score,
         hiu.total_answers_received,
         tc.tag,
         tc.tag_post_count,
         tc.avg_view_count
ORDER BY hiu.posts_count * tc.tag_post_count DESC
LIMIT 100;