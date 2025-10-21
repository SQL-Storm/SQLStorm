-- {"query": "24068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2826} 
WITH PostBase AS (
      -- Base data for question posts with outer joins and NULL logic
      SELECT p.Id,
             p.Title,
             COALESCE(u.DisplayName,'[deleted]')          AS OwnerName,
             COALESCE(p.Score,0)                         AS VoteScore,
             COALESCE(p.AnswerCount,0)::int             AS AnswerCount,
             COALESCE(pc.CommentCount,0)::int           AS CommentCount,
             -- correlated sub‑query to count distinct commenters
             (SELECT COUNT(DISTINCT c.UserId)
                FROM Comments c
               WHERE c.PostId = p.Id)                   AS UniqueCommenters,
             p.Tags
        FROM Posts p
        LEFT JOIN Users u          ON p.OwnerUserId = u.Id
        LEFT JOIN (SELECT PostId, COUNT(*) AS CommentCount
                     FROM Comments
                    GROUP BY PostId) pc ON pc.PostId = p.Id
       WHERE p.PostTypeId = 1      -- only questions
),
TagAgg AS (
      -- Add tag aggregation and categorize score level
      SELECT pb.Id,
             pb.Title,
             pb.OwnerName,
             pb.VoteScore,
             pb.AnswerCount,
             pb.CommentCount,
             pb.UniqueCommenters,
             -- lateral outer join to explode tags and re‑aggregate
             (SELECT string_agg(t.TagName, ', ')
                FROM unnest( string_to_array( substring(pb.Tags,2,length(pb.Tags)-2),'><') ) AS tag
                JOIN Tags t ON t.TagName = tag )         AS TagsCombined,
             CASE WHEN pb.VoteScore > 10 THEN 'High' ELSE 'Low' END AS ScoreLevel
        FROM PostBase pb
),
TopScore AS (
      -- Top 10 by vote score, window function for ranking
      SELECT *, ROW_NUMBER() OVER (ORDER BY VoteScore DESC, CommentCount DESC) AS RN
        FROM TagAgg
       WHERE VoteScore IS NOT NULL
      ORDER BY VoteScore DESC
      LIMIT 10
),
TopComment AS (
      -- Top 10 by comment count, window function for ranking
      SELECT *, ROW_NUMBER() OVER (ORDER BY CommentCount DESC, VoteScore DESC) AS RN
        FROM TagAgg
       WHERE CommentCount IS NOT NULL
      ORDER BY CommentCount DESC
      LIMIT 10
),
Combined AS (
      -- Set operator to combine two result sets
      SELECT 'Score'   AS Criteria,
             Id, Title, OwnerName, VoteScore, CommentCount, UniqueCommenters,
             TagsCombined, ScoreLevel
        FROM TopScore
      UNION ALL
      SELECT 'Comment' AS Criteria,
             Id, Title, OwnerName, VoteScore, CommentCount, UniqueCommenters,
             TagsCombined, ScoreLevel
        FROM TopComment
)
SELECT *
  FROM Combined
 ORDER BY Criteria, VoteScore DESC, CommentCount DESC;