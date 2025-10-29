-- {"query": "5169.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 728} 
WITH TopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount,
    u.Reputation,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
),
RecentActivity AS (
  SELECT
    t.QuestionId,
    t.Title,
    t.CreationDate,
    t.OwnerUserId,
    t.OwnerName,
    t.Reputation,
    t.Score,
    t.ViewCount,
    t.AnswerCount,
    t.CommentCount,
    t.LastActivityDate,
    t.Tags,
    t.FavoriteCount,
    COUNT(*) OVER () AS total_questions
  FROM TopQuestions t
  WHERE t.rn_owner = 1
),
TagStats AS (
  SELECT
    unnest(string_to_array(substring(t.Tags, 2, length(t.Tags)-2), '><')) AS TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(t.Score) AS AvgScorePerTag,
    MAX(t.ViewCount) AS MaxViewsForTag
  FROM RecentActivity t
  GROUP BY TagName
),
CrossJoinStats AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.OwnerUserId,
    r.OwnerName,
    r.Reputation,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.CommentCount,
    r.LastActivityDate,
    r.Tags,
    r.FavoriteCount,
    COALESCE(vt.ClosedCnt, 0) AS CloseVotes,
    COALESCE(vt.UpVotes, 0) AS UpVotes,
    COALESCE(vt.DownVotes, 0) AS DownVotes,
    vt.LastVoteDate
  FROM RecentActivity r
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      MAX(CreationDate) AS LastVoteDate,
      SUM(CASE WHEN VoteTypeId = 6 THEN 1 ELSE 0 END) AS ClosedCnt
    FROM Votes
    GROUP BY PostId
  ) vt ON r.QuestionId = vt.PostId
)
SELECT
  c.QuestionId,
  c.Title,
  c.OwnerName,
  c.Reputation,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.CommentCount,
  c.LastActivityDate,
  c.Tags,
  c.FavoriteCount,
  c.CloseVotes,
  c.UpVotes,
  c.DownVotes,
  c.LastVoteDate,
  tsg.TagName,
  tsg.TagQuestionCount,
  tsg.AvgScorePerTag,
  tsg.MaxViewsForTag
FROM CrossJoinStats c
LEFT JOIN TagStats tsg
  ON ',' || c.Tags || ',' LIKE '%,' || tsg.TagName || ',%'
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 200;