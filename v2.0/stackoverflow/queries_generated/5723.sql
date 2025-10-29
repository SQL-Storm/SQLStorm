-- {"query": "5723.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 785} 
WITH
recent_active_questions AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
tag_aggregates AS (
  SELECT
    t.TagName,
    COUNT(*) AS question_count,
    AVG(p.ViewCount) AS avg_views,
    SUM(p.Score) AS total_score
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS tagsplit
  INNER JOIN Tags tt ON tt.TagName = tagsplit.TagName
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  HAVING COUNT(*) > 10
),
complex_stats AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score AS QuestionScore,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(v.UpVotes, 0) AS UpVotesFromVotes,
    COALESCE(v.DownVotes, 0) AS DownVotesFromVotes,
    CASE
      WHEN q.OwnerUserId IS NULL THEN 'anonymous'
      ELSE u.DisplayName
    END AS OwnerDisplayName,
    CASE
      WHEN q.OwnerUserId IS NULL THEN -1
      ELSE q.OwnerUserId
    END AS OwnerUserId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = q.OwnerUserId) AS OwnerBadges
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) AS v ON v.PostId = q.Id
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  ORDER BY q.LastActivityDate DESC
  LIMIT 50
)
SELECT
  cq.QuestionId,
  cq.Title,
  cq.Tags,
  cq.CreationDate,
  cq.LastActivityDate,
  cq.ViewCount,
  cq.QuestionScore,
  cq.AnswerCount,
  cq.UpVotesFromVotes,
  cq.DownVotesFromVotes,
  cq.OwnerDisplayName,
  cq.OwnerUserId,
  cq.OwnerBadges,
  ra.rn_owner AS OwnerRecentRank,
  ta.TagName,
  ta.question_count,
  ta.avg_views,
  ta.total_score
FROM complex_stats cq
LEFT JOIN recent_active_questions ra ON ra.Id = cq.QuestionId
LEFT JOIN unnest(array(
  SELECT t.TagName
  FROM (
    SELECT unnest(string_to_array(substr(cq.Tags, 2, length(cq.Tags)-2), '><')) AS TagName
  ) AS t
)) AS ta(TagName)
LEFT JOIN tag_aggregates ta ON ta.TagName = ta.TagName
WHERE ra.rn_owner IS NULL OR ra.rn_owner = 1
ORDER BY cq.LastActivityDate DESC
LIMIT 100;