-- {"query": "24047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3051} 
WITH
  question_base AS (
    SELECT p.Id            AS QuestionId,
           p.Title,
           p.Tags,
           p.OwnerUserId,
           p.LastActivityDate,
           p.AnswerCount,
           COALESCE(u.Reputation, 0)        AS UserReputation,
           u.DisplayName                   AS OwnerDisplayName,
           p.ClosedDate
    FROM   Posts p
    LEFT   JOIN Users u
           ON   p.OwnerUserId = u.Id
    WHERE  p.PostTypeId = 1
  ),

  vote_stats AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           COUNT(*)                                          AS TotalVotes
    FROM   Votes v
    GROUP  BY v.PostId
  ),

  duplicate_stats AS (
    SELECT pl.PostId,
           COUNT(*) AS DuplicateCount
    FROM   PostLinks pl
    WHERE  pl.LinkTypeId = 3
    GROUP  BY pl.PostId
  ),

  comment_counts AS (
    SELECT c.PostId,
           COUNT(*) AS CommentCount
    FROM   Comments c
    GROUP  BY c.PostId
  ),

  tag_tokens AS (
    SELECT qb.QuestionId,
           unnest(
             string_to_array(
               substring(qb.Tags, 2, length(qb.Tags)-2),
               '><'
             )
           ) AS Tag
    FROM   question_base qb
  ),

  tag_freq AS (
    SELECT Tag,
           COUNT(*) AS Frequency
    FROM   tag_tokens
    GROUP  BY Tag
  ),

  ranked_questions AS (
    SELECT qb.*,
           COALESCE(vs.UpVotes, 0)          AS UpVotes,
           COALESCE(vs.DownVotes, 0)        AS DownVotes,
           COALESCE(ds.DuplicateCount, 0)   AS DuplicateCount,
           COALESCE(cc.CommentCount, 0)     AS CommentCount,
           rank() OVER (ORDER BY COALESCE(vs.UpVotes, 0) DESC,
                                   qb.LastActivityDate DESC) AS QRank,
           qb.ClosedDate IS NULL            AS IsOpen
    FROM   question_base qb
    LEFT   JOIN vote_stats vs
           ON   qb.QuestionId = vs.PostId
    LEFT   JOIN duplicate_stats ds
           ON   qb.QuestionId = ds.PostId
    LEFT   JOIN comment_counts cc
           ON   qb.QuestionId = cc.PostId
  ),

  filtered AS (
    SELECT *
    FROM   ranked_questions
    WHERE  AnswerCount >= 5
      AND  UpVotes > 0
    UNION ALL
    SELECT *
    FROM   ranked_questions
    WHERE  DownVotes > 0
      AND  UpVotes < 10
  ),

  final_query AS (
    SELECT f.*,
           (SELECT string_agg(t.Tag, ',' ORDER BY t.Tag)
            FROM   tag_tokens t
            WHERE  t.QuestionId = f.QuestionId) AS TagList
    FROM   filtered f
  )

SELECT *,
       CASE WHEN IsOpen THEN 'Open' ELSE 'Closed' END AS Status,
       COALESCE(UserReputation, 0) AS Reputation,
       OwnerDisplayName
FROM   final_query
ORDER  BY QRank
LIMIT  20;