-- {"query": "4356.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1108} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Focus on edits and rollbacks
  ),
  LatestEdits AS (
    SELECT
      PostId,
      UserId,
      EditDate,
      EditType
    FROM RankedPostEdits
    WHERE
      rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      COUNT(DISTINCTCASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(DISTINCTCASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId AND c.PostId = p.Id
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId AND v.PostId = p.Id
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.Score,
      p.ViewCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount,
      p.AnswerCount AS PostAnswerCount,
      LEAST(p.CreationDate, p.LastActivityDate) AS FirstActivityDate,
      GREATEST(p.CreationDate, p.LastActivityDate) AS LastActivityDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount AS UserCommentCount,
  ua.UpVoteCount,
  ua.DownVoteCount,
  pe.PostId,
  pe.Title,
  pe.PostTypeName,
  pe.Score,
  pe.ViewCount,
  pe.PostCommentCount,
  pe.FavoriteCount,
  pe.PostAnswerCount,
  pe.PostStatus,
  le.EditType AS LastEditType,
  le.EditDate AS LastEditDate,
  (
    ua.UpVoteCount * 1.0 / NULLIF(ua.DownVoteCount, 0)
  ) AS UpDownVoteRatio,
  DATE_PART('day', AGE(ua.LastPostDate, ua.CreationDate)) AS AccountAgeInDays,
  COALESCE(le.EditDate, pe.LastActivityDate) AS EffectiveLastActivity
FROM UserActivity AS ua
LEFT JOIN PostEngagement AS pe
  ON ua.UserId = pe.OwnerUserId
LEFT JOIN LatestEdits AS le
  ON pe.PostId = le.PostId
WHERE
  ua.Reputation > 1000
  AND ua.TotalPosts > 5
  AND pe.PostId IS NOT NULL
  AND pe.Score > 0
  AND (
    pe.PostTypeName = 'Question' OR pe.PostTypeName = 'Answer'
  )
  AND ua.DisplayName IS NOT NULL
  AND LENGTH(ua.DisplayName) > 5
  AND ua.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%' -- Basic alphanumeric check for display names
ORDER BY
  pe.Score DESC,
  ua.Reputation DESC,
  EffectiveLastActivity DESC
LIMIT 100;
