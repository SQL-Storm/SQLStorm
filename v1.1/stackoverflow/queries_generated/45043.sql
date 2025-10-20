-- {"query": "45043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 98642, "output_tokens": 17389} 
WITH TopUserTags AS (
  SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    t.TagName, 
    COUNT(p.Id) AS PostCount,
    RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tags(TagName) ON true
  JOIN Tags t ON t.TagName = tags.TagName
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, t.TagName
)
SELECT 
  UserId,
  DisplayName,
  STRING_AGG(TagName || ' (' || PostCount || ')', ', ' ORDER BY PostCount DESC) AS TopTags,
  SUM(PostCount) AS TotalTaggedPosts
FROM TopUserTags
WHERE TagRank <= 3
GROUP BY UserId, DisplayName
HAVING SUM(PostCount) > 50
ORDER BY TotalTaggedPosts DESC
LIMIT 100;