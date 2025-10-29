-- {"query": "5713.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 788} 
WITH
RecentActiveQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
PopularTags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagActivity AS (
  SELECT
    t.tag,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    MAX(p.CreationDate) AS last_question
  FROM PopularTags t
  JOIN Posts p ON p.Id = t.OwnerUserId
  GROUP BY t.tag
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate > NOW() - INTERVAL '30 days'
    AND v.VoteTypeId IN (2,3,10,11,16)
),
PostHistorySummary AS (
  SELECT
    ph.PostId,
    MAX(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS WasClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS WasHot
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  GROUP BY ph.PostId
)
SELECT
  rq.QuestionId,
  rq.Title,
  rq.CreationDate AS QuestionCreationDate,
  rq.ViewCount,
  rq.Score AS QuestionScore,
  rq.LastActivityDate,
  rq.AnswerCount,
  rq.CommentCount,
  pa.avg_score AS AvgTagScore,
  ht.WasClosed,
  ht.WasHot,
  us.UserId,
  us.DisplayName AS UserDisplayName,
  us.Reputation,
  us.UserCreationDate,
  us.LastAccessDate,
  us.Location,
  us.Views,
  us.UpVotes,
  us.DownVotes,
  ub.BadgeCount
FROM RecentActiveQuestions rq
LEFT JOIN (
  SELECT
    t.tag,
    AVG(p.Score) AS avg_score
  FROM PopularTags t
  JOIN Posts p ON p.Id = t.OwnerUserId
  GROUP BY t.tag
) pa ON pa.tag = rq.Tags
LEFT JOIN PostHistorySummary ht ON ht.PostId = rq.QuestionId
LEFT JOIN UserStats us ON us.UserId = rq.OwnerUserId
LEFT JOIN RecentVotes rv ON rv.PostId = rq.QuestionId
LEFT JOIN (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
) ub ON ub.UserId = us.UserId
ORDER BY rq.LastActivityDate DESC
LIMIT 100;