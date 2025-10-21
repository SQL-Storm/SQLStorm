-- {"query": "330.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17610} 
WITH
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.PostId IN (SELECT Id FROM Posts x WHERE x.OwnerUserId = u.Id)
    ) AS CommentsOnUserPosts,
    (SELECT STRING_AGG(tag, ',')
     FROM (
       SELECT DISTINCT t.TagName AS tag
       FROM Posts pp
       LEFT JOIN LATERAL unnest(string_to_array(substr(pp.Tags, 2, length(pp.Tags) - 2), '><')) AS tn(tag) ON TRUE
       LEFT JOIN Tags t ON t.TagName = tn.tag
       WHERE pp.OwnerUserId = u.Id
     ) s
    ) AS TagsList
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
top_post AS (
  SELECT UserId, PostId, Title, Score, LastActivityDate
  FROM (
     SELECT p.OwnerUserId AS UserId,
            p.Id AS PostId,
            p.Title,
            p.Score,
            p.LastActivityDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
     FROM Posts p
     WHERE p.PostTypeId = 1
  ) s
  WHERE rn = 1
),
top_tag AS (
  SELECT u.Id AS UserId,
         t.TagName,
         SUM(p.Score) AS TagScore,
         COUNT(*) AS TagPostCount,
         ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY SUM(p.Score) DESC, COUNT(*) DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tagname(tag) ON TRUE
  LEFT JOIN Tags t ON t.TagName = tagname.tag
  GROUP BY u.Id, t.TagName
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalScore,
  ua.TotalViews,
  ua.AvgScore,
  ua.LastActive,
  ua.CommentsOnUserPosts,
  ua.TagsList,
  tp.PostId AS TopPostId,
  tp.Title AS TopPostTitle,
  tp.Score AS TopPostScore,
  tp.LastActivityDate AS TopPostLastActive,
  utt.TagName AS TopTagName,
  utt.TagScore AS TopTagScore,
  utt.TagPostCount AS TopTagPostCount
FROM user_activity ua
LEFT JOIN top_post tp ON tp.UserId = ua.UserId
LEFT JOIN (SELECT * FROM top_tag WHERE rn = 1) utt ON utt.UserId = ua.UserId
ORDER BY ua.TotalScore DESC
LIMIT 100;