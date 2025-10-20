-- {"query": "55059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2000} 
WITH top_users AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation
    FROM   Users u
    WHERE  u.Reputation > 50000
    ORDER  BY u.Reputation DESC
    LIMIT  100
),
user_questions AS (
    SELECT p.Id               AS QuestionId,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Title,
           p.Tags,
           p.FavoriteCount,
           p.AnswerCount,
           u.DisplayName      AS OwnerDisplayName
    FROM   Posts p
    JOIN   top_users u ON p.OwnerUserId = u.Id
    WHERE  p.PostTypeId = 1          -- only questions
),
expanded_tags AS (
    SELECT q.QuestionId,
           trim(both '<>' FROM unnest(string_to_array(q.Tags, '><'))) AS Tag
    FROM   user_questions q
),
tag_aggregates AS (
    SELECT e.Tag,
           COUNT(*)                         AS TagQuestionCount,
           SUM(q.Score)                     AS TagScoreSum,
           AVG(q.ViewCount)                 AS TagAvgViews
    FROM   expanded_tags e
    JOIN   user_questions q ON e.QuestionId = q.QuestionId
    GROUP  BY e.Tag
),
question_votes AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
           MAX(v.CreationDate)                               AS LastVoteDate
    FROM   Votes v
    JOIN   user_questions q ON v.PostId = q.QuestionId
    GROUP  BY v.PostId
),
duplicate_links AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           pl.CreationDate
    FROM   PostLinks pl
    JOIN   user_questions q ON pl.PostId = q.QuestionId
    WHERE  pl.LinkTypeId = 3   -- Duplicate
),
recent_comments AS (
    SELECT c.PostId,
           COUNT(*) FILTER (WHERE c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
                                         AS RecentCommentCount,
           MAX(c.CreationDate)                 AS LastCommentDate
    FROM   Comments c
    JOIN   user_questions q ON c.PostId = q.QuestionId
    GROUP  BY c.PostId
)
SELECT q.QuestionId,
       q.Title,
       q.CreationDate,
       q.Score,
       q.ViewCount,
       q.AnswerCount,
       q.FavoriteCount,
       q.OwnerDisplayName,
       tv.UpVotes,
       tv.DownVotes,
       tv.Favorites,
       tv.LastVoteDate,
       rc.RecentCommentCount,
       rc.LastCommentDate,
       dl.RelatedPostId          AS DuplicateOf,
       dl.CreationDate           AS DuplicateLinkDate,
       array_agg(DISTINCT et.Tag) AS Tags,
       ta.TagQuestionCount,
       ta.TagScoreSum,
       ta.TagAvgViews
FROM   user_questions q
LEFT   JOIN question_votes tv         ON tv.PostId = q.QuestionId
LEFT   JOIN recent_comments rc       ON rc.PostId = q.QuestionId
LEFT   JOIN duplicate_links dl       ON dl.PostId = q.QuestionId
LEFT   JOIN expanded_tags et         ON et.QuestionId = q.QuestionId
LEFT   JOIN tag_aggregates ta        ON ta.Tag = et.Tag
GROUP  BY q.QuestionId,
          q.Title,
          q.CreationDate,
          q.Score,
          q.ViewCount,
          q.AnswerCount,
          q.FavoriteCount,
          q.OwnerDisplayName,
          tv.UpVotes,
          tv.DownVotes,
          tv.Favorites,
          tv.LastVoteDate,
          rc.RecentCommentCount,
          rc.LastCommentDate,
          dl.RelatedPostId,
          dl.CreationDate,
          ta.TagQuestionCount,
          ta.TagScoreSum,
          ta.TagAvgViews
ORDER  BY q.Score DESC,
          q.ViewCount DESC
LIMIT  200;