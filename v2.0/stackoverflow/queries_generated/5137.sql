-- {"query": "5137.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 946} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.LastEditorUserId,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActiveQuestion
  FROM (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, char_length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.Score,
      p.ViewCount,
      p.LastActivityDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '365 days'
  ) AS t_tags
  GROUP BY t.TagName
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.ProfileImageUrl,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
activity_summary AS (
  SELECT
    q.PostId,
    q.OwnerUserId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    COALESCE(vt.TotalVotes, 0) AS TotalVotes,
    COALESCE(vt.UpMod, 0) AS UpModVotes,
    COALESCE(vt.DownMod, 0) AS DownModVotes,
    CASE
      WHEN q.AnswerCount > 0 THEN 'Answered'
      ELSE 'Unanswered'
    END AS AnswerStatus
  FROM recent_questions q
  LEFT JOIN (
    SELECT
      Pv.PostId,
      SUM(CASE WHEN Pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
      SUM(CASE WHEN Pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
      SUM(CASE WHEN Pv.VoteTypeId = 6 THEN 1 ELSE 0 END) AS TotalCloseVotes,
      SUM(CASE WHEN Pv.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
      SUM(CASE WHEN Pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod,
      SUM(CASE WHEN Pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownMod
    FROM Votes Pv
    GROUP BY Pv.PostId
  ) vt ON vt.PostId = q.Id
)
SELECT
  a.PostId,
  a.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  a.Title,
  a.CreationDate,
  a.LastActivityDate,
  a.ViewCount,
  a.TotalVotes,
  a.UpModVotes,
  a.DownModVotes,
  a.AnswerStatus,
  rs.LastActiveQuestion,
  ts.TagName,
  ts.QuestionCount AS TagQuestionCount,
  ts.AvgScore AS TagAvgScore,
  ts.TotalViews AS TagTotalViews,
  upn.rn AS TopUserRank
FROM activity_summary a
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN (
  SELECT
    t.TagName,
    t.QuestionCount,
    t.AvgScore,
    t.TotalViews,
    t.LastActiveQuestion
  FROM tag_stats t
  ORDER BY t.QuestionCount DESC
  LIMIT 1
) ts ON true
LEFT JOIN LATERAL (
  SELECT
    qn.rn
  FROM top_users qn
  ORDER BY qn.rn ASC
  LIMIT 1
) upn ON true
WHERE a.ViewCount >= 100
  AND a.TotalVotes >= 5
ORDER BY a.LastActivityDate DESC
LIMIT 100;