-- {"query": "54069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2976} 
WITH tag_usage AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id)                        AS tot_posts,
        SUM(p.Score)                                AS tot_score,
        AVG(p.Score)                                AS avg_score,
        MIN(p.Score)                                AS min_score,
        MAX(p.Score)                                AS max_score,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS tot_upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS tot_downvotes
    FROM Posts p
    JOIN Tags t
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Votes v
      ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
top_tags AS (
    SELECT *
    FROM tag_usage
    ORDER BY tot_posts DESC
    LIMIT 10
),
user_tag_counts AS (
    SELECT
        t.TagName,
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id)                        AS user_posts,
        SUM(p.Score)                                AS user_score,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS user_upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS user_downvotes
    FROM Posts p
    JOIN Tags t
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Votes v
      ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, p.OwnerUserId
),
top_user_per_tag AS (
    SELECT
        utc.TagName,
        utc.UserId,
        u.DisplayName,
        utc.user_posts,
        utc.user_score,
        utc.user_upvotes,
        utc.user_downvotes,
        ROW_NUMBER() OVER (PARTITION BY utc.TagName ORDER BY utc.user_posts DESC, utc.user_score DESC) AS rn
    FROM user_tag_counts utc
    JOIN Users u
      ON u.Id = utc.UserId
)
SELECT
    tt.TagName,
    tt.tot_posts,
    tt.tot_score,
    tt.avg_score,
    tt.min_score,
    tt.max_score,
    tt.tot_upvotes,
    tt.tot_downvotes,
    tu.UserId,
    tu.DisplayName,
    tu.user_posts,
    tu.user_score,
    tu.user_upvotes,
    tu.user_downvotes
FROM top_tags tt
LEFT JOIN top_user_per_tag tu
  ON tt.TagName = tu.TagName AND tu.rn = 1
ORDER BY tt.tot_posts DESC;