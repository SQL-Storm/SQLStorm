WITH top_users AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS row_num
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, u.DisplayName
),
top_posts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS row_num
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
post_tags AS (
  SELECT
    p.Id AS post_id,
    TRIM(tag) AS TagName
  FROM
    Posts p,
    UNNEST(
      CASE
        WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
        ELSE regexp_split_to_array(
          regexp_replace(p.Tags, '^<|>$', ''), -- remove leading < and trailing >
          '><'
        )
      END
    ) AS t(tag)
),
top_tags AS (
  SELECT 
    pt.TagName, 
    COUNT(DISTINCT pt.post_id) AS num_posts,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT pt.post_id) DESC) AS row_num
  FROM 
    post_tags pt
  GROUP BY 
    pt.TagName
)
SELECT 
  tu.Id AS user_id, 
  tu.DisplayName AS user_name, 
  tu.total_upvotes, 
  tu.total_downvotes, 
  tp.Id AS post_id, 
  tp.Title AS post_title, 
  tp.Score AS post_score, 
  tp.ViewCount AS post_view_count, 
  tt.TagName AS top_tag
FROM 
  top_users tu
JOIN 
  top_posts tp ON tu.row_num = tp.row_num
JOIN 
  top_tags tt ON tu.row_num = tt.row_num
WHERE 
  tu.row_num <= 10
  AND tp.row_num <= 10
  AND tt.row_num <= 10
ORDER BY 
  tu.total_upvotes DESC;