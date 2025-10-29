WITH RecentActiveQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_user
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
QualifiedQuestions AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.ViewCount,
    q.Score,
    q.CreationDate,
    q.LastActivityDate,
    q.OwnerUserId,
    q.OwnerDisplayName,
    ta.TagName AS PrimaryTag,
    ta.TagCount,
    ROW_NUMBER() OVER (ORDER BY q.LastActivityDate DESC, q.Score DESC, q.ViewCount DESC) AS rn
  FROM RecentActiveQuestions q
  LEFT JOIN LATERAL (
    SELECT TagName, TagCount FROM TopTags t
    WHERE t.ExcerptPostId = q.QuestionId
    ORDER BY TagCount DESC
    LIMIT 1
  ) ta ON true
  WHERE q.rn_by_user = 1
    AND q.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
),
CompletionStats AS (
  SELECT
    pq.QuestionId,
    pq.Title,
    pq.ViewCount,
    pq.Score,
    pq.CreationDate,
    pq.LastActivityDate,
    pq.OwnerUserId,
    pq.OwnerDisplayName,
    pq.PrimaryTag,
    COALESCE(CM1.AnswerCount, 0) AS AnswerCount,
    COALESCE(CM3.CommentCount, 0) + COALESCE(CM2.CommentCount, 0) AS CommentCount,
    COALESCE(CM2.FavoriteCount, 0) AS FavoriteCount,
    COALESCE(CM4.UpVotes, 0) AS UpVotes,
    COALESCE(CM4.DownVotes, 0) AS DownVotes,
    COALESCE(B.Bounty, 0) AS Bounty,
    COALESCE(Ans.AnswerCount, 0) AS AnsAnswerCount
  FROM QualifiedQuestions pq
  LEFT JOIN (
    SELECT
      p.ParentId AS Qid,
      COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
  ) CM1 ON CM1.Qid = pq.QuestionId
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 6 THEN 1 ELSE 0 END) AS CommentCount,
      SUM(CASE WHEN VoteTypeId = 9 THEN 1 ELSE 0 END) AS FavoriteCount
    FROM Votes
    GROUP BY PostId
  ) CM2 ON CM2.PostId = pq.QuestionId
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) CM3 ON CM3.PostId = pq.QuestionId
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId IN (2,16) THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) CM4 ON CM4.PostId = pq.QuestionId
  LEFT JOIN (
    SELECT
      p.Id AS QuestionId,
      COALESCE(SUM(v.BountyAmount),0) AS Bounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
  ) B ON B.QuestionId = pq.QuestionId
  LEFT JOIN (
    SELECT
      p.ParentId AS Qid,
      COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
  ) Ans ON Ans.Qid = pq.QuestionId
)
SELECT
  cs.QuestionId,
  cs.Title,
  cs.ViewCount,
  cs.Score,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.OwnerUserId,
  cs.OwnerDisplayName,
  cs.PrimaryTag,
  cs.AnswerCount,
  cs.CommentCount,
  cs.FavoriteCount,
  COALESCE(vt.Name, 'Unknown') AS LastActionType
FROM CompletionStats cs
LEFT JOIN Votes v ON v.PostId = cs.QuestionId AND v.VoteTypeId = 6
LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
WHERE
  cs.LastActivityDate >= (SELECT MIN(LastActivityDate) FROM CompletionStats) - INTERVAL '7 days'
GROUP BY
  cs.QuestionId,
  cs.Title,
  cs.ViewCount,
  cs.Score,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.OwnerUserId,
  cs.OwnerDisplayName,
  cs.PrimaryTag,
  cs.AnswerCount,
  cs.CommentCount,
  cs.FavoriteCount,
  vt.Name
ORDER BY cs.LastActivityDate DESC, cs.ViewCount DESC
LIMIT 100;