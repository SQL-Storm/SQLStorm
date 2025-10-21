-- {"query": "36076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 359} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(p.Id) AS PostsCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesCount,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTags
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      ub.UserId,
      tt.Name
    FROM (
      SELECT OwnerUserId AS UserId, unnest(string_to_array(Tags, '>')) AS Tag
      FROM Posts
      WHERE PostTypeId = 1
    ) s
    LEFT JOIN Tags t ON t.TagName = s.Tag
  ) t ON t.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  PostsCount DESC, LastPostDate DESC
LIMIT 100;