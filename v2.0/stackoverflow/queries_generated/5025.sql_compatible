WITH 
RecentActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    COUNT(DISTINCT a.Id) AS AnswerCount
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
  GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, p.FavoriteCount
),
TaggedQuestions AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.AnswerCount,
    t.TagName
  FROM RecentActiveQuestions r
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(trim(BOTH ' ' FROM substr(p.Tags, 2, length(p.Tags)-2)), '> <')) AS TagName
    FROM Posts p WHERE p.Id = r.PostId
  ) t
),
QualityScores AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.AnswerCount,
    q.TagName,
    (CASE WHEN u.Reputation > 10000 THEN 5
          WHEN u.Reputation > 1000 THEN 3
          ELSE 1 END)
      + (CASE WHEN q.ViewCount > 1000 THEN 2 ELSE 0 END)
      + (CASE WHEN q.AnswerCount > 5 THEN 4 ELSE 0 END) AS RawScore
  FROM TaggedQuestions q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  WHERE q.TagName IS NOT NULL
),
Ranked AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    ViewCount,
    Score,
    OwnerUserId,
    AnswerCount,
    TagName,
    RawScore,
    ROW_NUMBER() OVER (
      PARTITION BY TagName
      ORDER BY RawScore DESC, CreationDate DESC
    ) AS TagRank
  FROM QualityScores
),
VotesActivity AS (
  SELECT
    r.PostId,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvote,
    MAX(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS HasDeletionVote,
    MAX(CASE WHEN v.VoteTypeId = 12 THEN 1 ELSE 0 END) AS HasSpamVote,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Ranked r
  LEFT JOIN Votes v ON v.PostId = r.PostId
  GROUP BY r.PostId
),
DerivedMetrics AS (
  SELECT
    v.PostId,
    r.Title,
    r.TagName,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    v.HasUpvote,
    v.HasDeletionVote,
    v.HasSpamVote,
    COALESCE(v.LastVoteDate, r.CreationDate) AS ActivityDate,
    (CASE
       WHEN v.HasUpvote = 1 AND v.HasDeletionVote = 0 THEN 1
       WHEN v.HasDeletionVote = 1 THEN -1
       ELSE 0
     END) AS NetVoteSignal,
    (SELECT AVG(LENGTH(p.Body)) FROM Posts p WHERE p.Id = v.PostId) AS BodyLengthAvg,
    v.LastVoteDate
  FROM Ranked r
  LEFT JOIN VotesActivity v ON v.PostId = r.PostId
),
FinalResults AS (
  SELECT
    PostId,
    Title,
    TagName,
    CreationDate,
    ViewCount,
    Score,
    AnswerCount,
    NetVoteSignal,
    LastVoteDate,
    BodyLengthAvg,
    ROW_NUMBER() OVER (
      ORDER BY NetVoteSignal DESC NULLS LAST,
               LastVoteDate DESC NULLS LAST,
               BodyLengthAvg DESC NULLS LAST
    ) AS Rank
  FROM DerivedMetrics d
  UNION ALL
  SELECT
    r.PostId,
    r.Title,
    r.TagName,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    CAST(NULL AS integer) AS NetVoteSignal,
    CAST(NULL AS timestamp) AS LastVoteDate,
    CAST(NULL AS double precision) AS BodyLengthAvg,
    ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS Rank
  FROM DerivedMetrics r
  WHERE r.NetVoteSignal < 0
)
SELECT
  PostId,
  Title,
  TagName,
  CreationDate,
  ViewCount,
  Score,
  AnswerCount,
  NetVoteSignal,
  LastVoteDate,
  BodyLengthAvg,
  Rank
FROM FinalResults
WHERE Rank <= 100
ORDER BY Rank ASC, PostId ASC;