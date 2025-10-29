-- {"query": "5784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 791}
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    ARRAY_AGG(CASE WHEN v.VoteTypeId IN (2,3) THEN v.VoteTypeId END) FILTER (WHERE v.VoteTypeId IS NOT NULL) AS UpDownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY
  GROUP BY
    p.Id, p.PostTypeId, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.LastActivityDate,
    p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ContentLicense,
    u.Reputation, u.DisplayName, u.AccountId
),
TopTags AS (
  SELECT
    TRIM(tag) AS TagName,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId
  FROM Posts p,
       UNNEST(string_to_array(
         CASE
           WHEN p.Tags LIKE '<%>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2)
           ELSE p.Tags
         END
       , '><')) AS t(tag)
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
CorrelatedTitles AS (
  SELECT
    r.PostId,
    r.Title AS PostTitle,
    (
      SELECT STRING_AGG(tt.TagName, ',')
      FROM TopTags tt
      WHERE tt.PostId = r.PostId
    ) AS TagsOnPost,
    r.OwnerUserId,
    r.Reputation,
    r.LastActivityDate,
    r.Score
  FROM RecentActivity r
  WHERE r.PostTypeId = 1
),
VarianceWindow AS (
  SELECT
    ct.PostId,
    ct.PostTitle,
    ct.TagsOnPost,
    ct.OwnerUserId,
    ct.Reputation,
    ct.LastActivityDate,
    ct.Score,
    ROW_NUMBER() OVER (PARTITION BY ct.OwnerUserId ORDER BY ct.LastActivityDate DESC) AS rn,
    AVG(ct.Score) OVER (PARTITION BY ct.OwnerUserId) AS AvgUserScore,
    STDDEV_SAMP(ct.Score) OVER (PARTITION BY ct.OwnerUserId) AS ScoreStdDev
  FROM CorrelatedTitles ct
)
SELECT
  vw.PostId,
  vw.PostTitle,
  vw.TagsOnPost,
  vw.OwnerUserId,
  vw.Reputation,
  vw.AvgUserScore,
  vw.ScoreStdDev,
  rt.PostCount AS RelatedTagPostCount,
  wt.AvgScore AS TopTagAvgScore
FROM VarianceWindow vw
LEFT JOIN TagStats rt ON vw.TagsOnPost LIKE '%' || rt.TagName || '%'
LEFT JOIN (
  SELECT
    t.TagName,
    AVG(p.Score) AS AvgScore
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
) wt ON wt.TagName = (
    SELECT tag
    FROM UNNEST(string_to_array(
      COALESCE(
        CASE
          WHEN vw.TagsOnPost IS NULL THEN ''
          WHEN vw.TagsOnPost LIKE '<%>' THEN SUBSTRING(vw.TagsOnPost FROM 2 FOR CHAR_LENGTH(vw.TagsOnPost)-2)
          ELSE vw.TagsOnPost
        END
      , '')
    , ', ')) AS unnested(tag)
    WHERE tag <> ''
    LIMIT 1
  )
WHERE vw.rn = 1
ORDER BY vw.Reputation DESC, vw.AvgUserScore DESC
LIMIT 50;