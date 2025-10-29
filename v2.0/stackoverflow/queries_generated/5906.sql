-- {"query": "5906.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 879} 
WITH
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Users u
  WHERE u.DeletionDate IS NULL OR u.DeletionDate IS NOT NULL -- placeholder to emphasize filtering if exists
),
TagHotness AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) OVER (PARTITION BY t.TagName) AS AvgPostScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' OR POSITION(t.TagName IN p.Tags) > 0
  GROUP BY t.TagName, t.Count
),
ComplexPostStats AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.FavoriteCount,
    -- Correlated subquery: number of comments by post owner on same day
    (SELECT COUNT(*) FROM Comments c
     WHERE c.PostId = p.Id AND c.UserId = p.OwnerUserId AND c.CreationDate::date = p.CreationDate::date) AS OwnerCommentsSameDay,
    -- Window function: rank posts per day by Score then ViewCount
    ROW_NUMBER() OVER (PARTITION BY DATE(p.CreationDate) ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS DayRank
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
FilteredPosts AS (
  SELECT
    c.*
  FROM ComplexPostStats c
  LEFT JOIN PostLinks pl ON pl.PostId = c.Id
  WHERE c.Score IS NOT NULL
    AND (c.Tags IS NOT NULL AND position('sql' IN lower(c.Tags)) > 0)
),
AggregatedVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses
  FROM Votes v
  GROUP BY v.PostId
),
Final AS (
  SELECT
    fp.*,
    av.UpVotes,
    av.DownVotes,
    av.BountyStarts,
    av.BountyCloses,
    tt.AvgPostScore,
    tt.QuestionCount,
    tt.AnswerCount
  FROM FilteredPosts fp
  LEFT JOIN AggregatedVotes av ON av.PostId = fp.Id
  LEFT JOIN TagHotness tt ON true
  ORDER BY DayRank, fp.CreationDate
)
SELECT
  f.Id AS PostId,
  f.Title,
  f.PostTypeId,
  f.Score,
  f.ViewCount,
  f.CreationDate,
  f.LastActivityDate,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.AnswerCount,
  f.CommentCount,
  f.Tags,
  f.FavoriteCount,
  f.OwnerCommentsSameDay,
  f.DayRank,
  f.UpVotes,
  f.DownVotes,
  f.BountyStarts,
  f.BountyCloses,
  f.AvgPostScore,
  f.QuestionCount,
  f.AnswerCount AS TagRelatedAnswers
FROM Final f
WHERE f.DayRank <= 100
;