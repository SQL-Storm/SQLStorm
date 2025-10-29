-- {"query": "4141.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1611} 

WITH
  PostSummary AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN p.PostTypeId = 1
        THEN JSON_EXTRACT(p.Tags, '$')
        ELSE '[]'
      END AS TagsArray,
      CASE
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
        THEN 1
        ELSE 0
      END AS HasAcceptedAnswer,
      (
        SELECT
          COUNT(*)
        FROM
          Comments c
        WHERE
          c.PostId = p.Id
      ) AS CommentCountSubquery,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM
          Votes v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVoteCountSubquery,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM
          Votes v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 3
      ) AS DownVoteCountSubquery,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequenceForUser
    FROM
      Posts p
      JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(Score) AS AverageScore,
      MAX(PostCreationDate) AS LatestPostDate,
      COUNT(DISTINCT CASE WHEN PostSequenceForUser = 1 THEN PostId ELSE NULL END) AS IsMostRecentPost
    FROM
      PostSummary
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      UserId
  ),
  PostVoteSummary AS (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotes,
      COUNT(CASE WHEN VoteTypeId = 5 THEN 1 ELSE NULL END) AS Favorites
    FROM
      Votes
    WHERE
      VoteTypeId IN (2, 3, 5)
    GROUP BY
      PostId
  ),
  ClosedQuestions AS (
    SELECT
      PostId,
      COUNT(*) AS CloseVoteCount
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId = 10
    GROUP BY
      PostId
  ),
  RecentHotQuestions AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastHotDate
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (52, 53)
    GROUP BY
      PostId
    HAVING
      MAX(CreationDate) > DATE('now', '-30 days')
  )
SELECT
  ps.PostId,
  ps.PostTypeName,
  ps.OwnerUserId,
  ps.OwnerDisplayName,
  ps.PostCreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.ClosedDate,
  ps.CommunityOwnedDate,
  ps.HasAcceptedAnswer,
  ps.CommentCountSubquery,
  ps.UpVoteCountSubquery,
  ps.DownVoteCountSubquery,
  COALESCE(pvs.UpVotes, 0) AS TotalUpVotes,
  COALESCE(pvs.DownVotes, 0) AS TotalDownVotes,
  COALESCE(pvs.Favorites, 0) AS TotalFavorites,
  COALESCE(cq.CloseVoteCount, 0) AS TotalCloseVotes,
  CASE
    WHEN ps.PostCreationDate < DATE('now', '-1 year') AND ps.Score > 100 THEN 'Veteran High Score'
    WHEN ps.PostCreationDate < DATE('now', '-3 months') AND ps.Score > 50 THEN 'Established High Score'
    WHEN ps.Score > 20 THEN 'High Score'
    WHEN ps.AnswerCount > 10 THEN 'Highly Answered'
    WHEN ps.CommentCount > 20 THEN 'Highly Commented'
    ELSE 'Standard'
  END AS PostCategorization,
  ua.TotalPosts AS UserTotalPosts,
  ua.QuestionCount AS UserQuestionCount,
  ua.AnswerCount AS UserAnswerCount,
  ua.AverageScore AS UserAverageScore,
  CASE
    WHEN rhq.PostId IS NOT NULL THEN 'Hot'
    ELSE 'Not Hot'
  END AS HotStatus,
  SUBSTRING(ps.TagsArray, 2, LENGTH(ps.TagsArray) - 2) AS CleanTags,
  CASE
    WHEN ps.OwnerDisplayName IS NULL THEN 'Anonymous'
    WHEN INSTR(ps.OwnerDisplayName, ' ') > 0 THEN 'Has Space'
    WHEN LENGTH(ps.OwnerDisplayName) > 20 THEN 'Long Name'
    ELSE 'Standard Name'
  END AS OwnerNameType,
  CASE
    WHEN ps.ClosedDate IS NOT NULL AND ps.Score < 0 THEN 'Negatively Scored Closed'
    WHEN ps.ClosedDate IS NOT NULL THEN 'Positively Scored Closed'
    WHEN ps.Score < 0 THEN 'Negatively Scored Open'
    ELSE 'Positively Scored Open'
  END AS ScoreAndStatus,
  (
    SELECT
      COUNT(pl.Id)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = ps.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount
FROM
  PostSummary ps
  LEFT JOIN UserActivity ua
  ON ps.OwnerUserId = ua.UserId
  LEFT JOIN PostVoteSummary pvs
  ON ps.PostId = pvs.PostId
  LEFT JOIN ClosedQuestions cq
  ON ps.PostId = cq.PostId
  LEFT JOIN RecentHotQuestions rhq
  ON ps.PostId = rhq.PostId
WHERE
  ps.OwnerUserId IS NOT NULL
  AND ps.PostCreationDate > DATE('now', '-2 years')
  AND ps.Score > -5
ORDER BY
  ps.PostCreationDate DESC
LIMIT 1000;
