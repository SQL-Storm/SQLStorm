-- {"query": "5431.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 859} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ClosedDate IS NULL
    AND p.LastActivityDate > DATEADD(day, -365, GETDATE())
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE rp.PostTypeId = 1) AS QuestionCount,
    SUM(rp.ViewCount) FILTER (WHERE rp.PostTypeId = 1) AS TotalViews,
    AVG(rp.Score) FILTER (WHERE rp.PostTypeId = 1) AS AvgScore,
    MAX(rp.LastActivityDate) AS LastActive
  FROM (
    SELECT
      p.PostTypeId,
      UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) AS t
  JOIN RankedPosts rp ON rp.Id = t.Id
  GROUP BY t.TagName
),
ActiveVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    vt.Name AS VoteName,
    u.DisplayName AS VoterName
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.CreationDate >= DATEADD(day, -90, GETDATE())
),
CrossJoinStats AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerName,
    rp.Reputation,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.Tags,
    a.Title AS AnswerTitle,
    a.OwnerName AS AnswerOwnerName,
    a.Score AS AnswerScore,
    ROW_NUMBER() OVER (ORDER BY rp.LastActivityDate DESC) AS overall_rank
  FROM RankedPosts rp
  LEFT JOIN Posts a ON a.ParentId = rp.Id AND a.PostTypeId = 2
  WHERE rp.rn_by_type = 1
),
FinalSet AS (
  SELECT
    c.*,
    tv.TagName,
    ts.QuestionCount,
    ts.TotalViews,
    ts.AvgScore,
    av.VoteName,
    av.VoterName
  FROM CrossJoinStats c
  LEFT JOIN Tags t ON t.IsModeratorOnly = 0
  LEFT JOIN TagStats ts ON ts.TagName = substring(c.Tags FROM 3 FOR char_length(c.Tags)-4)
  LEFT JOIN ActiveVotes av ON av.PostId = c.PostId
)
SELECT
  rf.PostId,
  rf.Title AS PostTitle,
  rf.OwnerName,
  rf.Reputation AS OwnerReputation,
  rf.CreationDate AS PostCreationDate,
  rf.LastActivityDate,
  rf.ViewCount,
  rf.Score,
  rf.Tags,
  rf.AnswerTitle,
  rf.AnswerOwnerName,
  rf.AnswerScore,
  rf.overall_rank,
  COALESCE(rf.TagName, 'untagged') AS PeakTag,
  rf.QuestionCount,
  rf.TotalViews,
  rf.AvgScore
FROM FinalSet rf
LEFT JOIN TagStats rfts ON rf.TagName = rfts.TagName
ORDER BY rf.overall_rank
LIMIT 100;