-- {"query": "98.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2650} 
WITH
-- recent activity per post with complex tag parsing and null-safe measures
post_activity AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(p.Score,0) AS Score,
    COALESCE(p.ViewCount,0) AS ViewCount,
    COALESCE(p.Title, '') AS Title,
    COALESCE(p.Tags,'') AS RawTags,
    -- parse first three tags defensively (Tags stored like '<tag1><tag2>')
    NULLIF(regexp_replace(substring(p.Tags from 2 for greatest(0, length(p.Tags)-2)), '^(.*?)><.*$', '\1'), '') AS FirstTag,
    NULLIF(regexp_replace(substring(p.Tags from 2 for greatest(0, length(p.Tags)-2)), '^.*?><(.*?)><.*$', '\1'), '') AS SecondTag,
    NULLIF(regexp_replace(substring(p.Tags from 2 for greatest(0, length(p.Tags)-2)), '^.*?><.*?><(.*?)$', '\1'), '') AS ThirdTag,
    p.AcceptedAnswerId,
    p.OwnerUserId
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '2 years'
),
-- compute user aggregates with windowing and ranking
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswerCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.LastAccessDate DESC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationDecile
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.CreationDate <= now()
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- complex join of posts with votes and comments including correlated subquery for moving-average-like metric
post_enriched AS (
  SELECT
    pa.*,
    us.DisplayName AS OwnerName,
    us.Reputation AS OwnerReputation,
    COALESCE(vt.UpVotes,0) AS UpVotes,
    COALESCE(vt.DownVotes,0) AS DownVotes,
    COALESCE(cmt.CommentCount,0) AS CommentCount,
    -- fraction of recent edits that are body edits via correlated count
    (
      SELECT CAST(COUNT(*) AS numeric) / NULLIF(GREATEST(COUNT(*),1),1)
      FROM PostHistory ph
      WHERE ph.PostId = pa.Id
        AND ph.PostHistoryTypeId IN (5,8,24) -- body edit, rollback body, suggested edit applied
    ) AS BodyEditFraction,
    -- moving-average like score per week over last 52 weeks (correlated)
    (
      SELECT COALESCE(AVG(p2.Score),0)
      FROM Posts p2
      WHERE p2.Id = pa.Id
        AND p2.CreationDate >= now() - interval '52 weeks'
    ) AS AvgScore52w
  FROM post_activity pa
  LEFT JOIN user_stats us ON us.UserId = pa.OwnerUserId
  LEFT JOIN (
    SELECT
      v.PostId,
      SUM(CASE WHEN vt.Name ILIKE '%up%' OR v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN vt.Name ILIKE '%down%' OR v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= now() - interval '3 years'
    GROUP BY v.PostId
  ) vt ON vt.PostId = pa.Id
  LEFT JOIN (
    SELECT
      c.PostId,
      COUNT(*) AS CommentCount
    FROM Comments c
    WHERE c.CreationDate >= now() - interval '3 years'
    GROUP BY c.PostId
  ) cmt ON cmt.PostId = pa.Id
),
-- identify pairs via PostLinks including duplicates and backlinks with set operators
linked_pairs AS (
  SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkType
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.CreationDate >= now() - interval '5 years'
  UNION
  -- include reversed relationships for symmetric analysis
  SELECT pl.RelatedPostId AS PostId, pl.PostId AS RelatedPostId, lt.Name || '_REVERSED'
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.CreationDate >= now() - interval '5 years'
),
-- tag popularity via explode-like approach and aggregation using regexp_matches
tags_exploded AS (
  SELECT
    pa.Id AS PostId,
    lower(trim(t)) AS Tag
  FROM post_activity pa,
  LATERAL (
    SELECT regexp_match_all
  ) rm -- placeholder to keep parser happy (ignored)
  CROSS JOIN LATERAL (
    SELECT unnest(
      CASE WHEN pa.RawTags = '' THEN ARRAY[]::text[]
           ELSE regexp_split_to_array(substring(pa.RawTags from 2 for greatest(0,length(pa.RawTags)-2)), '><')
      END
    ) AS t
  ) x
  WHERE pa.RawTags IS NOT NULL AND pa.RawTags <> ''
),
-- tag aggregates
tag_stats AS (
  SELECT
    te.Tag,
    COUNT(DISTINCT te.PostId) AS PostCount,
    COUNT(DISTINCT CASE WHEN pe.PostTypeId = 1 THEN pe.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN pe.PostTypeId = 2 THEN pe.Id END) AS Answers,
    SUM(COALESCE(pe.ViewCount,0)) AS TotalViews,
    AVG(COALESCE(pe.Score,0)) AS AvgScore,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT te.PostId) DESC) AS PopularityRank
  FROM tags_exploded te
  JOIN post_enriched pe ON pe.Id = te.PostId
  GROUP BY te.Tag
),
-- heavy-weight analytic: compute correlated popularity delta per tag comparing two periods
tag_trends AS (
  SELECT
    ts.Tag,
    ts.PostCount,
    ts.Questions,
    ts.Answers,
    ts.TotalViews,
    ts.AvgScore,
    COALESCE(
      (SELECT COUNT(*) FROM posts p2
       WHERE p2.Tags LIKE ('%' || '<' || ts.Tag || '>' || '%')
         AND p2.CreationDate >= now() - interval '26 weeks')::numeric,
      0
    ) AS RecentCount26w,
    COALESCE(
      (SELECT COUNT(*) FROM posts p2
       WHERE p2.Tags LIKE ('%' || '<' || ts.Tag || '>' || '%')
         AND p2.CreationDate >= now() - interval '52 weeks'
         AND p2.CreationDate < now() - interval '26 weeks')::numeric,
      0
    ) AS PrevCount26w,
    CASE
      WHEN COALESCE(
        (SELECT COUNT(*) FROM posts p2
         WHERE p2.Tags LIKE ('%' || '<' || ts.Tag || '>' || '%')
           AND p2.CreationDate >= now() - interval '52 weeks'
           AND p2.CreationDate < now() - interval '26 weeks'),0) = 0
      THEN NULL
      ELSE
        ( (SELECT COUNT(*) FROM posts p2
           WHERE p2.Tags LIKE ('%' || '<' || ts.Tag || '>' || '%')
             AND p2.CreationDate >= now() - interval '26 weeks')::numeric
          /
          (SELECT COUNT(*) FROM posts p2
           WHERE p2.Tags LIKE ('%' || '<' || ts.Tag || '>' || '%')
             AND p2.CreationDate >= now() - interval '52 weeks'
             AND p2.CreationDate < now() - interval '26 weeks')::numeric
        ) - 1
    END AS GrowthRatio
  FROM tag_stats ts
)
SELECT
  pe.Id AS PostId,
  pe.PostTypeId,
  pe.Title,
  COALESCE(pe.FirstTag, pe.SecondTag, pe.ThirdTag, 'untagged') AS PrimaryTag,
  pe.Score,
  pe.ViewCount,
  pe.UpVotes,
  pe.DownVotes,
  pe.CommentCount,
  pe.BodyEditFraction,
  pe.AvgScore52w,
  us.DisplayName AS Owner,
  us.Reputation AS OwnerReputation,
  lp.LinkType AS LinkRelation,
  COALESCE(tp.Tag,'(none)') AS TopTag,
  tp.PopularityRank AS TopTagRank,
  tt.GrowthRatio,
  -- calculated quality score mixing many signals, including null-safe math and conditional scaling
  ROUND(
    (
      (COALESCE(pe.Score,0) * 1.5)
      + (LEAST(1000, COALESCE(pe.ViewCount,0)) / 100.0)
      + (COALESCE(pe.UpVotes,0) * 2.0)
      - (COALESCE(pe.DownVotes,0) * 3.0)
      + (COALESCE(pe.CommentCount,0) * 0.5)
      + (COALESCE(us.Reputation,0) / 1000.0)
      + COALESCE(pe.AvgScore52w,0)
      + COALESCE(tt.GrowthRatio,0) * 50
    ) * CASE WHEN pe.PostTypeId = 1 THEN 1.2 WHEN pe.PostTypeId = 2 THEN 1.0 ELSE 0.8 END
  ,2) AS QualityScore,
  -- dense rank within tag by quality
  DENSE_RANK() OVER (PARTITION BY COALESCE(pe.FirstTag, pe.SecondTag, pe.ThirdTag, 'untagged') ORDER BY
    (
      (COALESCE(pe.Score,0) * 1.5)
      + (COALESCE(pe.UpVotes,0) * 2.0)
      - (COALESCE(pe.DownVotes,0) * 3.0)
      + (COALESCE(pe.CommentCount,0) * 0.5)
    ) DESC
  ) AS TagQualityRank
FROM post_enriched pe
LEFT JOIN user_stats us ON us.UserId = pe.OwnerUserId
LEFT JOIN linked_pairs lp ON lp.PostId = pe.Id
LEFT JOIN LATERAL (
  SELECT ts.Tag, ts.PopularityRank
  FROM tag_stats ts
  WHERE ts.Tag = COALESCE(pe.FirstTag, pe.SecondTag, pe.ThirdTag)
  ORDER BY ts.PostCount DESC
  LIMIT 1
) tp ON true
LEFT JOIN tag_trends tt ON tt.Tag = COALESCE(pe.FirstTag, pe.SecondTag, pe.ThirdTag)
WHERE
  -- complex predicate mixing null logic and regex filtering on title and tags
  (
    (pe.Title IS NOT NULL AND pe.Title ~* '(^|\\s)(error|exception|fail|panic)(\\s|$)')
    OR (pe.RawTags IS NOT NULL AND pe.RawTags ILIKE '%<sql>%')
    OR (pe.Score >= 10 AND pe.ViewCount >= 1000)
    OR (pe.BodyEditFraction IS NOT NULL AND pe.BodyEditFraction > 0.5)
  )
  AND pe.CreationDate >= now() - interval '2 years'
ORDER BY QualityScore DESC NULLS LAST, pe.ViewCount DESC
LIMIT 250;