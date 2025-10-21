-- {"query": "252.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9206} 
WITH
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Tags,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.LastActivityDate,
         p.LastEditDate,
         LENGTH(p.Title) AS TitleLen
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
),
Enriched AS (
  SELECT rq.PostId,
         rq.Title,
         rq.TitleLen,
         rq.Tags,
         rq.OwnerUserId,
         rq.CreationDate,
         rq.Score,
         rq.ViewCount,
         rq.LastActivityDate,
         rq.LastEditDate,
         COALESCE(u.DisplayName, 'Unknown') AS OwnerDisplayName,
         (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.PostId AND a.PostTypeId = 2) AS AnswerCount,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCount,
         (SELECT MIN(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = rq.PostId) AS FirstHistoryDate,
         (SELECT COUNT(*) FROM unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS t(TagName)) AS TagCount,
         LOWER(rq.Title) AS TitleLower
  FROM RecentQuestions rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
),
SetA AS (
  SELECT * FROM Enriched
  ORDER BY Score DESC
  LIMIT 50
),
SetB AS (
  SELECT * FROM Enriched
  ORDER BY ViewCount DESC
  LIMIT 50
),
UnionSet AS (
  SELECT PostId, Title, TitleLen, Tags, OwnerUserId, OwnerDisplayName, CreationDate, Score, ViewCount,
         LastActivityDate, LastEditDate, AnswerCount, CommentCount, FirstHistoryDate, TagCount,
         TitleLower, 1 AS Source
  FROM SetA
  UNION ALL
  SELECT PostId, Title, TitleLen, Tags, OwnerUserId, OwnerDisplayName, CreationDate, Score, ViewCount,
         LastActivityDate, LastEditDate, AnswerCount, CommentCount, FirstHistoryDate, TagCount,
         TitleLower, 2 AS Source
  FROM SetB
),
Final AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY Source ORDER BY CreationDate DESC, ViewCount DESC, Score DESC) AS rn
  FROM UnionSet
)
SELECT
  PostId,
  Title,
  TitleLen,
  Tags,
  OwnerUserId,
  OwnerDisplayName,
  CreationDate,
  Score,
  ViewCount,
  LastActivityDate,
  LastEditDate,
  AnswerCount,
  CommentCount,
  FirstHistoryDate,
  TagCount,
  TitleLower,
  Source,
  rn
FROM Final
ORDER BY Source, rn;