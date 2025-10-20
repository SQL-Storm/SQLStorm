WITH monthly_user_activity AS (
  SELECT 
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    DATE_TRUNC('month', p.CreationDate) AS activity_month,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
    AVG(p.Score) AS avg_post_score,
    SUM(v.BountyAmount) AS total_bounty_offered,
    COUNT(DISTINCT ph.Id) AS edit_count
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
  LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8 AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
  LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6) AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
  WHERE u.Reputation >= 100
  GROUP BY u.Id, u.DisplayName, u.Reputation, DATE_TRUNC('month', p.CreationDate)
  HAVING COUNT(DISTINCT p.Id) > 0
),
top_tags_by_user AS (
  SELECT 
    mua.user_id,
    mua.activity_month,
    STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 20), ', ') AS popular_tags,
    COUNT(DISTINCT parsed.tag) AS total_tag_exposure
  FROM monthly_user_activity mua
  JOIN Posts p ON mua.user_id = p.OwnerUserId AND DATE_TRUNC('month', p.CreationDate) = mua.activity_month
  CROSS JOIN LATERAL (
    -- split tags like '<tag1><tag2>' into rows by extracting substrings between '<' and '>'
    SELECT
      TRIM(BOTH FROM SUBSTRING(tag_text FROM 1 FOR (CASE WHEN POSITION('>' IN tag_text) > 0 THEN POSITION('>' IN tag_text) - 1 ELSE LENGTH(tag_text) END))) AS tag
    FROM (
      SELECT regexp_split_to_table(p.Tags, '<') AS tag_text
    ) s
    WHERE tag_text IS NOT NULL AND tag_text <> ''
  ) parsed
  JOIN Tags t ON t.TagName = parsed.tag
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY mua.user_id, mua.activity_month
),
community_influence AS (
  SELECT 
    mua.user_id,
    mua.activity_month,
    COUNT(DISTINCT a.Id) AS accepted_answers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS referenced_posts,
    AVG(ua.UpVotes - ua.DownVotes) AS net_votes_received
  FROM monthly_user_activity mua
  JOIN Posts q ON mua.user_id = q.OwnerUserId AND q.PostTypeId = 1 AND DATE_TRUNC('month', q.CreationDate) = mua.activity_month
  JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.OwnerUserId != mua.user_id
  LEFT JOIN PostLinks pl ON q.Id = pl.PostId AND pl.LinkTypeId IN (1, 3)
  LEFT JOIN Users ua ON a.OwnerUserId = ua.Id
  GROUP BY mua.user_id, mua.activity_month
)
SELECT 
  mua.DisplayName AS user_name,
  mua.activity_month,
  mua.post_count,
  mua.question_count,
  mua.answer_count,
  ROUND(CAST(mua.avg_post_score AS numeric), 2) AS avg_score,
  COALESCE(tt.popular_tags, 'No tags') AS top_tags,
  mua.total_bounty_offered,
  mua.edit_count,
  COALESCE(ci.accepted_answers, 0) AS accepted_answers_given,
  COALESCE(ci.referenced_posts, 0) AS community_references,
  ROUND(CAST(COALESCE(ci.net_votes_received, 0) AS numeric), 0) AS net_votes,
  mua.Reputation
FROM monthly_user_activity mua
LEFT JOIN top_tags_by_user tt ON mua.user_id = tt.user_id AND mua.activity_month = tt.activity_month
LEFT JOIN community_influence ci ON mua.user_id = ci.user_id AND mua.activity_month = ci.activity_month
WHERE mua.post_count >= 5
ORDER BY mua.activity_month DESC, mua.post_count DESC, mua.Reputation DESC
LIMIT 1000;