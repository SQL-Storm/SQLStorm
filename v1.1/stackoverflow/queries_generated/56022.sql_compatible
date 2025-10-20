WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    p.PostTypeId = 2 AND v.VoteTypeId IN (2, 3)
  GROUP BY 
    u.Id, u.DisplayName
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(p.Id) AS PostCount
  FROM 
    Posts p
  JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  GROUP BY 
    t.TagName
)
SELECT 
  tu.Id, 
  tu.DisplayName, 
  tu.UpVotes, 
  tu.DownVotes, 
  tt.TagName, 
  tt.PostCount
FROM 
  TopUsers tu
JOIN 
  Posts p ON tu.Id = p.OwnerUserId
JOIN 
  PostLinks pl ON p.Id = pl.PostId
JOIN 
  Tags t ON pl.RelatedPostId = t.WikiPostId
JOIN 
  TopTags tt ON t.TagName = tt.TagName
WHERE 
  p.Score > 10 AND tt.PostCount > 100
GROUP BY
  tu.Id,
  tu.DisplayName,
  tu.UpVotes,
  tu.DownVotes,
  tt.TagName,
  tt.PostCount,
  p.Id,
  pl.PostId,
  pl.RelatedPostId,
  t.WikiPostId
ORDER BY 
  tu.UpVotes DESC, tt.PostCount DESC;