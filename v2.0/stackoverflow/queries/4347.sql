-- {"query": "4347.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2203}
WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  QuestionAnswers AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(a.Score) AS TotalAnswerScore,
      MAX(a.CreationDate) AS LatestAnswerDate
    FROM
      Posts p
      JOIN Posts a ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY
      p.Id
  ),
  PostEngagement AS (
    SELECT
      PostId,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoriteVotes,
      COUNT(Id) AS TotalVotes
    FROM
      Votes
    WHERE
      VoteTypeId IN (2, 3, 5)
    GROUP BY
      PostId
  ),
  RecentPosts AS (
    SELECT
      Id,
      Title,
      OwnerUserId,
      CreationDate,
      Score,
      ViewCount,
      AnswerCount,
      FavoriteCount,
      PostTypeId,
      Tags,
      ClosedDate
    FROM
      Posts
    WHERE
      CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 day'
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      COALESCE(upc.PostCount, 0) AS TotalPosts,
      COALESCE(SUM(CASE WHEN r.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
      COALESCE(SUM(CASE WHEN r.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
      COALESCE(SUM(pe.UpVotes), 0) AS TotalUpVotesReceived,
      COALESCE(SUM(CASE WHEN r.Score > 0 THEN 1 ELSE 0 END), 0) AS PostsWithPositiveScore,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank
    FROM
      Users u
      LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
      LEFT JOIN RecentPosts r ON u.Id = r.OwnerUserId
      LEFT JOIN PostEngagement pe ON r.Id = pe.PostId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      upc.PostCount
  )
SELECT
  rp.Title AS PostTitle,
  COALESCE(u.DisplayName, 'Deleted User') AS AuthorDisplayName,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  COALESCE(qa.AnswerCount, 0) AS NumberOfAnswers,
  COALESCE(qa.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(pe.UpVotes, 0) AS PostUpvotes,
  COALESCE(pe.DownVotes, 0) AS PostDownvotes,
  COALESCE(pe.FavoriteVotes, 0) AS PostFavoriteVotes,
  (
    rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)
  ) AS ScorePerViewRatio,
  CASE
    WHEN rp.PostTypeId = 1 THEN 'Question'
    WHEN rp.PostTypeId = 2 THEN 'Answer'
    WHEN rp.PostTypeId = 3 THEN 'Wiki'
    WHEN rp.PostTypeId = 5 THEN 'Tag Wiki'
    ELSE 'Other'
  END AS PostTypeName,
  CASE
    WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
    WHEN rp.FavoriteCount > 50 THEN 'Moderately Favorited'
    ELSE 'Less Favorited'
  END AS FavoriteStatus,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks pl
      WHERE
        pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Of'
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks pl
      WHERE
        pl.RelatedPostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Duplicate Links'
  END AS DuplicateStatus,
  ua.Reputation AS AuthorReputation,
  ua.TotalPosts AS AuthorTotalPosts,
  ua.QuestionCount AS AuthorQuestionCount,
  ua.AnswerCount AS AuthorAnswerCount,
  ua.TotalUpVotesReceived AS AuthorTotalUpvotesReceived,
  ua.ReputationRank AS AuthorReputationRank,
  SUBSTRING(rp.Tags FROM 2 FOR (CHAR_LENGTH(rp.Tags) - 2)) AS FormattedTags,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  COALESCE(
    (
      SELECT
        Name
      FROM
        CloseReasonTypes
      WHERE
        Id = (
          SELECT
            CAST(Comment AS INTEGER)
          FROM
            PostHistory
          WHERE
            PostId = rp.Id
            AND PostHistoryTypeId = 10
          ORDER BY
            CreationDate DESC
          LIMIT 1
        )
    ),
    'N/A'
  ) AS CloseReasonName
FROM
  RecentPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN QuestionAnswers qa ON rp.Id = qa.QuestionId
  LEFT JOIN PostEngagement pe ON rp.Id = pe.PostId
  LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
  rp.CreationDate >= cast('2024-10-01' as date) - INTERVAL '7 day' AND rp.PostTypeId IN (1, 2)
UNION
SELECT
  rp.Title AS PostTitle,
  COALESCE(u.DisplayName, 'Deleted User') AS AuthorDisplayName,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  COALESCE(qa.AnswerCount, 0) AS NumberOfAnswers,
  COALESCE(qa.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(pe.UpVotes, 0) AS PostUpvotes,
  COALESCE(pe.DownVotes, 0) AS PostDownvotes,
  COALESCE(pe.FavoriteVotes, 0) AS PostFavoriteVotes,
  (
    rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)
  ) AS ScorePerViewRatio,
  CASE
    WHEN rp.PostTypeId = 1 THEN 'Question'
    WHEN rp.PostTypeId = 2 THEN 'Answer'
    WHEN rp.PostTypeId = 3 THEN 'Wiki'
    WHEN rp.PostTypeId = 5 THEN 'Tag Wiki'
    ELSE 'Other'
  END AS PostTypeName,
  CASE
    WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
    WHEN rp.FavoriteCount > 50 THEN 'Moderately Favorited'
    ELSE 'Less Favorited'
  END AS FavoriteStatus,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks pl
      WHERE
        pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Of'
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks pl
      WHERE
        pl.RelatedPostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Duplicate Links'
  END AS DuplicateStatus,
  ua.Reputation AS AuthorReputation,
  ua.TotalPosts AS AuthorTotalPosts,
  ua.QuestionCount AS AuthorQuestionCount,
  ua.AnswerCount AS AuthorAnswerCount,
  ua.TotalUpVotesReceived AS AuthorTotalUpvotesReceived,
  ua.ReputationRank AS AuthorReputationRank,
  SUBSTRING(rp.Tags FROM 2 FOR (CHAR_LENGTH(rp.Tags) - 2)) AS FormattedTags,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  COALESCE(
    (
      SELECT
        Name
      FROM
        CloseReasonTypes
      WHERE
        Id = (
          SELECT
            CAST(Comment AS INTEGER)
          FROM
            PostHistory
          WHERE
            PostId = rp.Id
            AND PostHistoryTypeId = 10
          ORDER BY
            CreationDate DESC
          LIMIT 1
        )
    ),
    'N/A'
  ) AS CloseReasonName
FROM
  RecentPosts rp
  INNER JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN QuestionAnswers qa ON rp.Id = qa.QuestionId
  LEFT JOIN PostEngagement pe ON rp.Id = pe.PostId
  INNER JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE
  rp.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 day' AND rp.PostTypeId = 1
ORDER BY
  PostCreationDate DESC
LIMIT 100;