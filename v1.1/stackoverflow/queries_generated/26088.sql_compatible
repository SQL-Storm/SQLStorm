WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount, 
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RowNum
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId IN (1, 2)
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS RowNum
  FROM 
    Tags t
  JOIN 
    Posts p ON EXISTS (
      SELECT 1
      FROM (
        -- split Tags string like "<tag1><tag2>" into rows: dialect-agnostic approach using simple string matching
        SELECT p.Id AS PostId
      ) sub
      WHERE p.Tags IS NOT NULL
        AND ( '<' || t.TagName || '>' ) = ANY (regexp_split_to_array(p.Tags, '><'))
    )
  GROUP BY 
    t.TagName
),
UserVotes AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  JOIN 
    Votes v ON u.Id = v.UserId
  WHERE 
    v.VoteTypeId IN (2, 3)
  GROUP BY 
    u.Id, u.DisplayName
)
SELECT 
  tu.DisplayName, 
  tu.PostCount, 
  tu.QuestionCount, 
  tu.AnswerCount, 
  uv.UpVotes, 
  uv.DownVotes, 
  tt.TagName, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount AS PostAnswerCount, 
  p.CommentCount, 
  ph.Comment
FROM 
  TopUsers tu
JOIN 
  UserVotes uv ON tu.Id = uv.Id
JOIN 
  Posts p ON tu.Id = p.OwnerUserId
JOIN 
  PostHistory ph ON p.Id = ph.PostId
JOIN 
  TopTags tt ON p.Tags IS NOT NULL
    AND ('<' || tt.TagName || '>') = ANY (regexp_split_to_array(p.Tags, '><'))
WHERE 
  tu.RowNum <= 10 
  AND tt.RowNum <= 10 
  AND p.PostTypeId = 1 
  AND ph.PostHistoryTypeId = 2
GROUP BY
  tu.DisplayName,
  tu.PostCount,
  tu.QuestionCount,
  tu.AnswerCount,
  uv.UpVotes,
  uv.DownVotes,
  tt.TagName,
  p.Title,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  ph.Comment,
  tu.Id,
  uv.Id,
  p.Id,
  ph.PostId
ORDER BY 
  tu.PostCount DESC, 
  uv.UpVotes DESC, 
  p.Score DESC;