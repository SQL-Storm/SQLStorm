-- {"query": "5022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 892} 
WITH TopActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.DeletionDate IS NULL -- if available, otherwise ignore (not in schema)
),
RecentTagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
PopularWikis AS (
  SELECT
    w.Id AS WikiPostId,
    w.Title AS WikiTitle,
    w.OwnerUserId,
    w.LastEditDate,
    w.LastActivityDate,
    w.ContentLicense,
    COUNT(c.Id) AS CommentCountOnWiki
  FROM Posts w
  LEFT JOIN Comments c ON c.PostId = w.Id
  WHERE w.PostTypeId IN (4,5) -- TagWikiExcerpt / TagWiki
  GROUP BY w.Id, w.Title, w.OwnerUserId, w.LastEditDate, w.LastActivityDate, w.ContentLicense
),
CrossJoinBenchmark AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    vtype.Name AS VoteTypeName,
    t.TagName
  FROM TopActiveQuestions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN Votes vv ON vv.PostId = q.PostId
  LEFT JOIN VoteTypes vtype ON vtype.Id = CASE
    WHEN vv.VoteTypeId IS NULL THEN 0
    ELSE vv.VoteTypeId
  END
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE q.rn = 1
),
CombinedCP AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.CommentCount,
    c.AnswerCount,
    c.Reputation,
    c.DisplayName,
    c.Location,
    c.VoteTypeName,
    c.TagName
  FROM CrossJoinBenchmark c
  UNION ALL
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    NULL AS VoteTypeName,
    t.TagName
  FROM TopActiveQuestions p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.rn = 1
),
FinalOutput AS (
  SELECT
    PostId,
    Title,
    OwnerUserId,
    LastActivityDate,
    Score,
    ViewCount,
    CommentCount,
    AnswerCount,
    Reputation,
    DisplayName,
    Location,
    COALESCE(VoteTypeName, 'Unknown') AS VoteTypeName,
    COALESCE(TagName, '') AS TagName
  FROM CombinedCP
  ORDER BY LastActivityDate DESC
  LIMIT 100
)
SELECT * FROM FinalOutput;