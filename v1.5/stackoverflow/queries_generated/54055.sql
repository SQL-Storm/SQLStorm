-- {"query": "54055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2948} 

WITH
  recent_questions AS (
    SELECT p.Id,
           p.Title,
           p.CreationDate,
           p.OwnerUserId,
           p.Tags,
           COALESCE(a.AnswerCount,0) AS AnswerCount
      FROM Posts p
      LEFT JOIN LATERAL (
        SELECT COUNT(*) AS AnswerCount
          FROM Posts a
         WHERE a.ParentId = p.Id
           AND a.PostTypeId = 2
      ) a ON true
     WHERE p.PostTypeId = 1
       AND p.CreationDate >= NOW() - INTERVAL '30 days'
  ),
  vote_stats AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
           SUM(CASE WHEN v.VoteTypeId = 7 THEN 1 ELSE 0 END) AS Reopens
      FROM Votes v
     GROUP BY v.PostId
  ),
  tag_tokens AS (
    SELECT p.Id,
           token AS Tag
      FROM Posts p
      CROSS JOIN LATERAL (
        SELECT unnest( string_to_array( replace( replace(p.Tags, '<', ''), '>', '' ), ' ') ) AS token
      ) t
     WHERE p.PostTypeId = 1
  ),
  tag_counts AS (
    SELECT Tag,
           COUNT(*)          AS TotalTagCount,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS TagRank
      FROM tag_tokens
     GROUP BY Tag
  )
SELECT fq.Id,
       fq.Title,
       fq.CreationDate,
       fq.AnswerCount,
       vs.Upvotes,
       vs.Downvotes,
       vs.Reopens,
       tt.Tag,
       tc.TotalTagCount
  FROM recent_questions fq
  LEFT JOIN vote_stats vs ON vs.PostId = fq.Id
  LEFT JOIN tag_tokens tt ON tt.Id = fq.Id
  LEFT JOIN tag_counts tc ON tc.Tag = tt.Tag
 ORDER BY vs.Upvotes DESC NULLS LAST,
          fq.CreationDate DESC
 LIMIT 200;
