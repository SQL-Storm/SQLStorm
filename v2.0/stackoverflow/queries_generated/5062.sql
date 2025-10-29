-- {"query": "5062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 825} 
WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    row_number() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
PopularTags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    t.Tag AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM PopularTags t
  JOIN Posts p ON p.PostTypeId = 1
    AND p.Tags LIKE '%' || t.Tag || '%' -- approximate link
  GROUP BY t.Tag
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > (CURRENT_DATE - INTERVAL '30 days')
),
CommentsSummary AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount24h,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  WHERE c.CreationDate >= (CURRENT_DATE - INTERVAL '1 day')
  GROUP BY c.PostId
),
VotesInfluence AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS NetVotes
  FROM Votes v
  GROUP BY v.PostId
),
Combined AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate,
    tq.LastActivityDate,
    tq.Score,
    tq.ViewCount,
    tq.OwnerUserId,
    tq.Tags,
    ts.QuestionCount,
    ts.AvgScore,
    ts.TotalViews,
    cs.CommentCount24h,
    vs.UpVotes,
    vs.DownVotes,
    vs.NetVotes,
    ru.DisplayName AS LastEditorName,
    u.Reputation,
    u.Location
  FROM TopQuestions tq
  LEFT JOIN TagStats ts ON tq.Tags LIKE '%' || ts.TagName || '%'
  LEFT JOIN RecentActivity ra ON ra.PostId = tq.PostId
  LEFT JOIN CommentsSummary cs ON cs.PostId = tq.PostId
  LEFT JOIN VotesInfluence vs ON vs.PostId = tq.PostId
  LEFT JOIN Posts lq ON lq.Id = tq.PostId
  LEFT JOIN Users u ON u.Id = tq.OwnerUserId
  LEFT JOIN Users ru ON ru.Id = lq.OwnerUserId
)
SELECT
  PostId,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerUserId,
  Tags,
  QuestionCount,
  AvgScore,
  TotalViews,
  CommentCount24h,
  UpVotes,
  DownVotes,
  NetVotes,
  LastEditorName,
  Reputation,
  Location
FROM Combined
WHERE
  rn <= 100
ORDER BY
  LastActivityDate DESC,
  NetVotes DESC,
  Score DESC
;