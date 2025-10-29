-- {"query": "5902.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 885}
WITH ranked_questions AS (
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
    (SELECT COUNT(*) FROM Posts ap WHERE ap.ParentId = p.Id AND ap.PostTypeId = 2) AS ChildAnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_date
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (SELECT MIN(CreationDate) FROM Posts)
),
top_per_day AS (
  SELECT *
  FROM ranked_questions
  WHERE rn_date = 1
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.DisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT STRING_AGG(CONCAT(b.Name, '(', b.Class, ')'), ', ')
     FROM Badges b WHERE b.UserId = u.Id) AS BadgesInfo
  FROM Users u
),
vote_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(*) AS VoteCount,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
complex_calc AS (
  SELECT
    t.PostId,
    t.Title,
    t.CreationDate,
    t.ViewCount,
    t.Score,
    t.CommentCount,
    t.AnswerCount,
    v.UpVotes,
    v.DownVotes,
    (t.Score * 1.0) +
      (CASE WHEN t.ViewCount > 1000 THEN 50 ELSE 0 END) +
      (CASE WHEN t.CommentCount > 10 THEN 20 ELSE 0 END) AS CustomScore,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgQuestionScore
  FROM top_per_day t
  LEFT JOIN vote_summary v ON v.PostId = t.PostId
),
final_result AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.ViewCount,
    c.Score,
    c.CommentCount,
    c.AnswerCount,
    c.UpVotes,
    c.DownVotes,
    c.CustomScore,
    c.AvgQuestionScore,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS Reputation,
    us.BadgesInfo AS BadgesInfo,
    us.BadgeCount AS BadgeCount,
    p.Tags AS Tags
  FROM complex_calc c
  LEFT JOIN Posts p ON p.Id = c.PostId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN user_stats us ON us.UserId = u.Id
)
SELECT
  fr.PostId,
  fr.Title,
  fr.Tags,
  fr.CreationDate,
  fr.ViewCount,
  fr.Score,
  fr.CommentCount,
  fr.AnswerCount,
  fr.UpVotes,
  fr.DownVotes,
  fr.CustomScore,
  fr.AvgQuestionScore,
  fr.OwnerDisplayName,
  fr.Reputation,
  fr.BadgesInfo,
  fr.BadgeCount,
  fr.Tags,
  (SELECT COUNT(*) FROM Posts ch WHERE ch.ParentId = fr.PostId AND ch.PostTypeId = 2) AS UndeletedChildren
FROM final_result fr
ORDER BY fr.CustomScore DESC, fr.AvgQuestionScore DESC, fr.CreationDate DESC
OFFSET 0
FETCH FIRST 100 ROWS ONLY;