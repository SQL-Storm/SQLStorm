WITH RecursiveKeywordPosts AS (
  SELECT
    p.Id,
    p.CreationDate,
    p.Title,
    p.Body
  FROM posts p
)
SELECT
  rkp.Id,
  rkp.CreationDate,
  rkp.Title,
  rkp.Body
FROM RecursiveKeywordPosts rkp
;