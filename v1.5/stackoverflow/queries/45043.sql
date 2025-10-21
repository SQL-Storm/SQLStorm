WITH TopUserTags AS (
  SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    t.TagName, 
    COUNT(p.Id) AS PostCount,
    RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  CROSS JOIN LATERAL (
    SELECT TRIM(value) AS TagName
    FROM UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS value
  ) AS tags
  JOIN Tags t ON t.TagName = tags.TagName
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, t.TagName
)
SELECT 
  UserId,
  DisplayName,
  STRING_AGG(TagName || ' (' || CAST(PostCount AS VARCHAR) || ')', ', ' ORDER BY PostCount DESC) AS TopTags,
  SUM(PostCount) AS TotalTaggedPosts
FROM TopUserTags
WHERE TagRank <= 3
GROUP BY UserId, DisplayName
HAVING SUM(PostCount) > 50
ORDER BY TotalTaggedPosts DESC
LIMIT 100;