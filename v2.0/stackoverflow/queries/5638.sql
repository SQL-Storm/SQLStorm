-- {"query": "5638.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 723}
WITH TopTagWikis AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    w.Id AS WikiPostId,
    w.Title AS WikiTitle,
    w.CreationDate AS WikiCreationDate,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.LastEditDate,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC, w.CreationDate DESC) AS rn
  FROM Tags t
  JOIN Posts w ON w.Id = t.WikiPostId
  WHERE w.PostTypeId = 5 AND t.IsModeratorOnly = FALSE
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    COALESCE(v.TotalUp, 0) AS UpVotes,
    COALESCE(v.TotalDown, 0) AS DownVotes,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn2
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
),
Combined AS (
  SELECT
    hw.TagName AS Tag,
    hw.TagCount,
    hw.WikiPostId,
    hw.WikiTitle,
    hw.WikiCreationDate,
    hw.OwnerUserId,
    hw.OwnerDisplayName,
    hw.LastEditDate,
    ra.PostId AS AnswerToPostId,
    ra.Title AS AnswerTitle,
    ra.PostTypeId AS AnswerPostType,
    ra.CreationDate AS AnswerCreationDate,
    ra.LastActivityDate AS AnswerLastActivityDate,
    ra.ViewCount AS AnswerViews,
    ra.Score AS AnswerScore,
    ra.UpVotes AS AnswerUp,
    ra.DownVotes AS AnswerDown,
    ra.rn2
  FROM TopTagWikis hw
  LEFT JOIN RecentActivity ra ON ra.PostId = hw.WikiPostId
  WHERE hw.rn = 1
),
Benchmark AS (
  SELECT
    Tag,
    TagCount,
    WikiPostId,
    WikiTitle,
    WikiCreationDate,
    OwnerUserId,
    OwnerDisplayName,
    LastEditDate,
    AnswerToPostId,
    AnswerTitle,
    AnswerPostType,
    AnswerCreationDate,
    AnswerLastActivityDate,
    AnswerViews,
    AnswerScore,
    AnswerUp,
    AnswerDown,
    rn2
  FROM Combined
)
SELECT
  Tag,
  TagCount,
  WikiPostId,
  WikiTitle,
  WikiCreationDate,
  OwnerUserId,
  OwnerDisplayName,
  LastEditDate,
  AnswerToPostId,
  AnswerTitle,
  AnswerPostType,
  AnswerCreationDate,
  AnswerLastActivityDate,
  AnswerViews,
  AnswerScore,
  AnswerUp,
  AnswerDown,
  rn2
FROM Benchmark
WHERE rn2 <= 50
ORDER BY Tag, WikiCreationDate DESC, AnswerLastActivityDate DESC;