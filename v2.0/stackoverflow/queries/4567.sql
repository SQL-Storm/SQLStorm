WITH
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      Score,
      AnswerCount,
      FavoriteCount,
      ROW_NUMBER() OVER (
        ORDER BY
          CreationDate DESC
      ) AS rn
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      Views,
      UpVotes,
      DownVotes,
      (cast('2024-10-01' as date) - CreationDate) AS account_age_days
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  QuestionTagCounts AS (
    SELECT
      p.Id AS PostId,
      t.TagName,
      COUNT(*) OVER (PARTITION BY t.TagName) AS TagPostCount
    FROM
      Posts p,
      LATERAL (
        SELECT unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS TagName
      ) t
    WHERE
      p.PostTypeId = 1
  ),
  UserPostEngagement AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
      SUM(CASE WHEN p.OwnerUserId = u.Id THEN p.Score ELSE 0 END) AS UserScoreOnTheirPosts
    FROM
      Users u
      LEFT JOIN PostHistory ph ON u.Id = ph.UserId
      LEFT JOIN Comments c ON u.Id = c.UserId
      LEFT JOIN Votes v ON u.Id = v.UserId
      LEFT JOIN Posts p ON ph.PostId = p.Id OR c.PostId = p.Id OR v.PostId = p.Id
    GROUP BY
      u.Id
  )
SELECT
  rq.Id AS QuestionId,
  rq.Title AS QuestionTitle,
  hru.DisplayName AS OwnerDisplayName,
  hru.Reputation AS OwnerReputation,
  hru.account_age_days AS OwnerAccountAgeDays,
  qts.TagName AS PrimaryTag,
  qts.TagPostCount AS PrimaryTagTotalCount,
  CASE
    WHEN rq.FavoriteCount > 0 THEN 'Favorited'
    WHEN rq.Score > 10 THEN 'Highly Scored'
    ELSE 'Standard'
  END AS QuestionStatus,
  up.PostHistoryCount AS UserPostHistoryCount,
  up.CommentCount AS UserCommentCount,
  up.UpVoteCount AS UserUpVotes,
  up.DownVoteCount AS UserDownVotes,
  COALESCE(up.UserScoreOnTheirPosts, 0) AS UserTotalScoreOnTheirPosts,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = rq.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts a WHERE a.ParentId = rq.Id AND a.Score > 0
    ) THEN 'HasAcceptedAnswer'
    ELSE 'NoAcceptedAnswer'
  END AS AnswerStatus
FROM
  RecentQuestions rq
JOIN
  HighReputationUsers hru ON rq.OwnerUserId = hru.Id
LEFT JOIN
  QuestionTagCounts qts ON rq.Id = qts.PostId
    AND qts.TagName = (
      SELECT t.TagName
      FROM (
        SELECT unnest(string_to_array(SUBSTRING(rq.Tags FROM 2 FOR (CHAR_LENGTH(rq.Tags) - 2)), '><')) AS TagName
      ) t
      ORDER BY t.TagName
      LIMIT 1
    )
LEFT JOIN
  UserPostEngagement up ON rq.OwnerUserId = up.UserId
WHERE
  rq.rn BETWEEN 1 AND 50
  AND hru.Reputation > 50000
  AND rq.AnswerCount > 0
  AND rq.FavoriteCount IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM Comments c WHERE c.PostId = rq.Id AND c.Score < 0
  )
UNION
SELECT
  rq.Id AS QuestionId,
  rq.Title AS QuestionTitle,
  hru.DisplayName AS OwnerDisplayName,
  hru.Reputation AS OwnerReputation,
  hru.account_age_days AS OwnerAccountAgeDays,
  qts.TagName AS PrimaryTag,
  qts.TagPostCount AS PrimaryTagTotalCount,
  CASE
    WHEN rq.FavoriteCount > 0 THEN 'Favorited'
    WHEN rq.Score > 10 THEN 'Highly Scored'
    ELSE 'Standard'
  END AS QuestionStatus,
  up.PostHistoryCount AS UserPostHistoryCount,
  up.CommentCount AS UserCommentCount,
  up.UpVoteCount AS UserUpVotes,
  up.DownVoteCount AS UserDownVotes,
  COALESCE(up.UserScoreOnTheirPosts, 0) AS UserTotalScoreOnTheirPosts,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = rq.Id AND pl.LinkTypeId = 1
  ) AS LinkedPostCount,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts a WHERE a.ParentId = rq.Id AND a.Score > 0
    ) THEN 'HasAcceptedAnswer'
    ELSE 'NoAcceptedAnswer'
  END AS AnswerStatus
FROM
  RecentQuestions rq
JOIN
  HighReputationUsers hru ON rq.OwnerUserId = hru.Id
LEFT JOIN
  QuestionTagCounts qts ON rq.Id = qts.PostId
    AND qts.TagName = (
      SELECT t.TagName
      FROM (
        SELECT unnest(string_to_array(SUBSTRING(rq.Tags FROM 2 FOR (CHAR_LENGTH(rq.Tags) - 2)), '><')) AS TagName
      ) t
      ORDER BY t.TagName DESC
      LIMIT 1
    )
LEFT JOIN
  UserPostEngagement up ON rq.OwnerUserId = up.UserId
WHERE
  rq.rn BETWEEN 51 AND 100
  AND hru.Reputation < 10000
  AND rq.AnswerCount < 5
  AND rq.Score < 0
  AND up.CommentCount > 100
  AND up.UpVoteCount IS NULL;