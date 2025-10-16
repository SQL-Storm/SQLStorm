-- {"query": "1522.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1340} 

WITH RecursiveTagHierarchy (TagId, TagName, Depth) AS (
    SELECT t.Id, t.TagName, 1
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
  UNION ALL
    SELECT t.Id, t.TagName, rh.Depth + 1
    FROM Tags t
    JOIN PostTags pt ON pt.TagId = t.Id
    JOIN Posts p ON p.Id = pt.PostId
    JOIN RecursiveTagHierarchy rh ON rh.TagId = pt.TagId AND rh.Depth < 3
  WHERE t.Id != rh.TagId
),
QuestionAntiCorrelatedVotes AS (
    SELECT p.Id AS PostId, u.Id AS UserId,
      (SELECT COUNT(*)
       FROM Votes vq
       WHERE vq.PostId = p.Id AND vq.UserId = u.Id AND vq.VoteTypeId IN (2,3)
      ) AS UserVotesCount,
      p.Score, LENGTH(p.Body) - LENGTH(REPLACE(p.Body, 'SQL', '')) / NULLIF(LENGTH('SQL'),0) AS SqlTermCount
    FROM Posts p
    CROSS JOIN Users u
    WHERE p.PostTypeId = 1 -- questions
),
RankingVotes AS (
  SELECT PostId, UserId, UserVotesCount,
         ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY UserVotesCount DESC, UserId) AS VoteRank
    FROM QuestionAntiCorrelatedVotes
    WHERE UserVotesCount IS NOT NULL AND UserVotesCount > 0
),
HighRankedVoteUsers AS (
  SELECT DISTINCT PostId, UserId
    FROM RankingVotes
    WHERE VoteRank <= 5
),
PostDetails AS (
  SELECT p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, 
         COALESCE(p.FavoriteCount,0) AS FavoriteCount,
         u.DisplayName AS OwnerName, u.Reputation,
         COALESCE((
           SELECT AVG(sc.Score)
           FROM Posts sc
           WHERE sc.OwnerUserId = p.OwnerUserId AND sc.PostTypeId = 1 AND sc.Id != p.Id
         ),0) AS OwnerQAvgScore,
         bt.Name AS TopBadgeName,
         pt.Name AS PostTypeName,
         closehist.Comment::int AS CloseReasonType
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN LATERAL (
      SELECT b.Name
      FROM Badges b 
      WHERE b.UserId = p.OwnerUserId
      ORDER BY b.Class ASC, b.Date DESC
      LIMIT 1
    ) AS bt ON true
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    LEFT JOIN PostHistory closehist ON closehist.PostId = p.Id 
        AND closehist.PostHistoryTypeId = 10 -- Post Closed
        AND closehist.CreationDate = (
          SELECT MAX(ph.CreationDate) 
          FROM PostHistory ph 
          WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        )
    WHERE p.PostTypeId IN (1,2) -- question or answer
),
CombinedResults AS (
  SELECT DISTINCT
     pd.*, relations.RelatedPostId, lt2.Name AS RelatedLinkType,
     STRING_AGG(DISTINCT cercob.EditedByUser, ', ') AS RecentEditors,
     STRING_AGG(DISTINCT t.TagName, '><') AS TagsAggregated,
     WINDOW_FUNCS.*
  FROM PostDetails pd
  LEFT JOIN PostLinks relations ON pd.Id = relations.PostId
  LEFT JOIN LinkTypes lt2 ON lt2.Id = relations.LinkTypeId
  LEFT JOIN (
      SELECT ph.PostId, STRING_AGG(u.DisplayName, ', ' ORDER BY ph.CreationDate DESC) AS EditedByUser
      FROM PostHistory ph
      LEFT JOIN Users u ON u.Id = ph.UserId
      WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.CreationDate >= NOW() - INTERVAL '30 days'
      GROUP BY ph.PostId
  ) cercob ON cercob.PostId = pd.Id
  LEFT JOIN POSTS_TAGS_RELATION PREL ON PREL.PostId = pd.Id -- placeholder for join to Tags, alias inside collect aggregation
  LEFT JOIN Tags t ON t.Id = ANY(string_to_array(trim(both '<>' from coalesce(pd.Tags, '')), '><')::int[]) OR ',' || pd.Tags || ',' LIKE '%,' || t.TagName || ',%'
  LEFT JOIN LATERAL (
    SELECT row_number() OVER (PARTITION BY pd.Id ORDER BY v.CreationDate DESC) AS VoteRank,
           v.VoteTypeId,
           COUNT(*) OVER (PARTITION BY pd.Id) AS TotalVotes,
           AVG(pd.Score) OVER() AS AvgScore
    FROM Votes v
    WHERE v.PostId = pd.Id
    LIMIT 50
  ) WINDOW_FUNCS ON true
  GROUP BY pd.Id, pd.Title, pd.Tags, pd.Score, pd.ViewCount, 
           pd.CreationDate, pd.FavoriteCount, pd.OwnerName, pd.Reputation,
           pd.OwnerQAvgScore, pd.TopBadgeName, pd.PostTypeName, relations.RelatedPostId, lt2.Name,
    WINDOW_FUNCS.VoteRank, WINDOW_FUNCS.VoteTypeId, WINDOW_FUNCS.TotalVotes, WINDOW_FUNCS.AvgScore, closehist.Comment
)
SELECT * FROM CombinedResults
WHERE 
-- Complicated expression predicates mixing nullchecks, math and booleans
   -- Select recently favorited Questions or those with high scores/reputation correlation with negative down votes yet lots of recent user activity,
   (
     (PostTypeName = 'Question' AND FavoriteCount > 5 AND Score/NULLIF(ViewCount,0) > 0.05 AND FavoriteCount > Score/2) OR
     (PostTypeName = 'Answer' AND Reputation > 1000 AND Score < 0 AND Score + 2 * FavoriteCount > 0)
   )
   AND (
   closehist.Comment::int IS NULL OR closehist.Comment::int NOT IN (101,105) -- Avoid widely closed duplicate/opinion posts age to mitigate bias
   )
ORDER BY FavoriteCount DESC NULLS LAST, Score DESC, Reputation DESC
LIMIT 100;
