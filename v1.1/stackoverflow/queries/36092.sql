SELECT
  INTO_TMP.t AS BenchmarkResult
FROM
  (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.ViewCount,
      p.Score,
      p.CreationDate,
      p.LastActivityDate,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      v.VoteTypeId,
      v.UserId AS VoterUserId,
      v.CreationDate AS VoteDate,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      COUNT(*) OVER () AS TotalRows,
      CAST(NULL AS VARCHAR) AS t
    FROM
      Posts p
      LEFT JOIN Votes v ON v.PostId = p.Id
      LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
      AND (p.ViewCount IS NOT NULL)
  ) AS INTO_TMP
WHERE
  TotalRows > 0
ORDER BY
  PostId
LIMIT 1000;