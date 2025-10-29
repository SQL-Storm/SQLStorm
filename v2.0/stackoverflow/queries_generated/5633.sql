-- {"query": "5633.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 717} 
WITH TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    p.OwnerUserId,
    p.LastEditDate,
    ARRAY_LENGTH(REGEXP_SPLIT_TO_ARRAY(p.Tags, '<>|</>'), 1) AS TagCount,
    COUNT(*) OVER () AS TotalPosts
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)  -- Questions and Answers
),
CorrelatedStats AS (
  SELECT
    t1.PostId,
    t1.PostTypeId,
    t1.CreationDate,
    t1.Score,
    t1.ViewCount,
    t1.Title,
    t1.Tags,
    t1.UserId,
    t1.UserName,
    t1.OwnerUserId,
    t1.LastEditDate,
    t1.TagCount,
    t2.Id AS RelatedPostId,
    t2.Title AS RelatedTitle,
    t2.CreationDate AS RelatedCreationDate,
    t2.Score AS RelatedScore,
    t2.ViewCount AS RelatedViewCount,
    t2.Tags AS RelatedTags,
    t2.OwnerUserId AS RelatedOwnerUserId
  FROM TaggedActivity t1
  LEFT JOIN Posts t2
    ON t1.PostId <> t2.Id
   AND t2.PostTypeId = 1
   AND t2.Tags && t1.Tags  -- rough overlap check only for performance; assumes array-like string overlap
   AND t2.CreationDate > t1.CreationDate
  GROUP BY
    t1.PostId, t1.PostTypeId, t1.CreationDate, t1.Score, t1.ViewCount, t1.Title, t1.Tags,
    t1.UserId, t1.UserName, t1.OwnerUserId, t1.LastEditDate, t1.TagCount,
    t2.Id, t2.Title, t2.CreationDate, t2.Score, t2.ViewCount, t2.Tags, t2.OwnerUserId
),
WindowAgg AS (
  SELECT
    PostId,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    Title,
    Tags,
    UserId,
    UserName,
    OwnerUserId,
    LastEditDate,
    TagCount,
    RelatedPostId,
    RelatedTitle,
    RelatedCreationDate,
    RelatedScore,
    RelatedViewCount,
    RelatedTags,
    RelatedOwnerUserId,
    ROW_NUMBER() OVER (
      PARTITION BY PostId
      ORDER BY RelatedScore DESC NULLS LAST, RelatedViewCount DESC NULLS LAST, RelatedCreationDate ASC
    ) AS rn
  FROM CorrelatedStats
)
SELECT
  PostId,
  PostTypeId,
  CreationDate,
  Score,
  ViewCount,
  Title,
  Tags,
  UserId,
  UserName,
  OwnerUserId,
  LastEditDate,
  TagCount,
  RelatedPostId,
  RelatedTitle,
  RelatedCreationDate,
  RelatedScore,
  RelatedViewCount,
  RelatedTags,
  RelatedOwnerUserId,
  rn
FROM WindowAgg
WHERE rn = 1
ORDER BY PostId, rn;