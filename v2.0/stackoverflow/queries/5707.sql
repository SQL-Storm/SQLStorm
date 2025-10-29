-- {"query": "5707.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1150}
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(p.Score,0) AS Score,
    COALESCE(p.ViewCount,0) AS ViewCount,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
),
popular_questions AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    r.CommentCount,
    r.Tags
  FROM (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.ViewCount,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.Tags,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.LastActivityDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Title IS NOT NULL
      AND p.Title <> ''
  ) AS r
  WHERE r.rn <= 50
),
diff_heat AS (
  SELECT
    tq.UserId,
    tq.DisplayName,
    tq.Reputation,
    q.PostId,
    q.Title AS QuestionTitle,
    q.ViewCount,
    q.Score AS QuestionScore,
    q.AnswerCount,
    q.CommentCount,
    v1.VoteCountUp,
    v2.VoteCountDown,
    v3.BountyAmount,
    (q.ViewCount * 1.0) / NULLIF(LEAD(q.Score) OVER (PARTITION BY q.OwnerUserId ORDER BY q.PostId), 0) AS velocity
  FROM top_users tq
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.ViewCount,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS lastUpVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount
  ) q ON q.OwnerUserId = tq.UserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCountUp
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v1 ON v1.PostId = q.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCountDown
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) v2 ON v2.PostId = q.PostId
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS BountyAmount
    FROM Votes
    WHERE VoteTypeId = 8 OR VoteTypeId = 9
    GROUP BY PostId
  ) v3 ON v3.PostId = q.PostId
  WHERE q.PostId IS NOT NULL
),
outer_join_example AS (
  SELECT
    t.DisplayName AS TopUser,
    pq.PostId,
    pq.Title AS QuestionTitle,
    pq.ViewCount,
    pq.Score AS QuestionScore,
    pq.AnswerCount,
    pq.CommentCount,
    d.ClosedReason
  FROM popular_questions pq
  LEFT JOIN (
    SELECT p.Id, c.Text AS ClosedReason
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    LEFT JOIN (SELECT Id, Text FROM PostHistory WHERE PostHistoryTypeId = 10) c ON c.Id = ph.Id
    WHERE p.ClosedDate IS NOT NULL
  ) d ON d.Id = pq.PostId
  RIGHT JOIN top_users t ON t.UserId = COALESCE(pq.PostId, t.UserId)
)
SELECT
  t.DisplayName AS top_user,
  t.Reputation AS top_reputation,
  pu.PostId,
  pu.QuestionTitle,
  pu.ViewCount,
  pu.QuestionScore,
  pu.AnswerCount,
  pu.CommentCount,
  COALESCE(r.velocity, 0) AS velocity,
  COALESCE(d.ClosedReason, 'OPEN') AS closed_status
FROM top_users t
JOIN outer_join_example pu ON pu.TopUser = t.DisplayName
LEFT JOIN diff_heat r ON r.PostId = pu.PostId
LEFT JOIN (
  SELECT p.Id, c.Text AS ClosedReason
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN (SELECT Id, Text FROM PostHistory WHERE PostHistoryTypeId = 10) c ON c.Id = ph.Id
  WHERE p.ClosedDate IS NOT NULL
) d ON d.Id = pu.PostId
GROUP BY
  t.DisplayName,
  t.Reputation,
  pu.PostId,
  pu.QuestionTitle,
  pu.ViewCount,
  pu.QuestionScore,
  pu.AnswerCount,
  pu.CommentCount,
  r.velocity,
  d.ClosedReason
ORDER BY t.Reputation DESC, pu.ViewCount DESC
LIMIT 200;