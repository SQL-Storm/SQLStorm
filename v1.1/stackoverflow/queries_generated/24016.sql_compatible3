WITH
  parsed_tags AS (
    SELECT
      p.Id                 AS PostId,
      p.Title              AS PostTitle,
      p.Score              AS PostScore,
      p.CreationDate       AS PostCreated,
      p.ViewCount          AS ViewCount,
      regexp_split_to_array( regexp_replace(regexp_replace(p.Tags, '^<', ''), '>$', ''), '><') AS TagsArray,
      p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),

  tag_counts AS (
    SELECT
      tag AS TagName,
      COUNT(*) AS QCount
    FROM parsed_tags,
    UNNEST(TagsArray) AS t(tag)
    GROUP BY tag
  ),

  user_vote_totals AS (
    SELECT
      v.UserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.UserId
  ),

  user_scores AS (
    SELECT
      u.Id              AS UserId,
      u.DisplayName,
      u.Reputation,
      COALESCE(vt.UpVotes, 0) - COALESCE(vt.DownVotes, 0) AS NetVoteScore
    FROM Users u
    LEFT JOIN user_vote_totals vt ON vt.UserId = u.Id
  ),

  duplicate_flag AS (
    SELECT
      pl.PostId              AS DuplicatePostId,
      pl.RelatedPostId       AS OriginalPostId,
      row_number() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn,
      pl.CreationDate
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
  ),

  recent_posts AS (
    SELECT
      pt.PostId,
      pt.PostTitle,
      pt.PostScore,
      pt.PostCreated,
      pt.ViewCount,
      pt.OwnerUserId,
      CASE WHEN df.rn = 1 THEN 'Duplicate' ELSE 'Normal' END AS Status,
      us.NetVoteScore,
      pt.TagsArray
    FROM parsed_tags pt
    LEFT JOIN duplicate_flag df  ON df.DuplicatePostId = pt.PostId
    LEFT JOIN user_scores us     ON us.UserId       = pt.OwnerUserId
    WHERE pt.PostCreated > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
  ),

  ranked_posts AS (
    SELECT
      rp.PostId,
      rp.PostTitle,
      rp.PostScore,
      rp.PostCreated,
      rp.ViewCount,
      rp.OwnerUserId,
      rp.Status,
      rp.NetVoteScore,
      rp.TagsArray,
      row_number() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.PostScore DESC) AS Rank
    FROM recent_posts rp
  ),

  status_totals AS (
    SELECT 'Normal'  AS Category, COUNT(*) AS Total FROM ranked_posts WHERE Status = 'Normal'
    UNION ALL
    SELECT 'Duplicate' AS Category, COUNT(*) AS Total FROM ranked_posts WHERE Status = 'Duplicate'
  ),

  final_view AS (
    SELECT
      u.Id            AS UserId,
      u.DisplayName,
      u.Reputation,
      rp.PostTitle,
      rp.PostScore,
      rp.NetVoteScore,
      rp.ViewCount,
      rp.Status,
      rp.Rank,
      tags.TagName,
      tc.QCount
    FROM Users u
    LEFT JOIN ranked_posts rp     ON rp.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
      SELECT t.tag AS TagName FROM UNNEST(COALESCE(rp.TagsArray, ARRAY[]::text[])) AS t(tag)
    ) tags ON tags.TagName IS NOT NULL
    LEFT JOIN tag_counts tc ON tc.TagName = tags.TagName
    WHERE rp.PostScore IS NOT NULL
    ORDER BY u.Reputation DESC, rp.PostScore DESC
    LIMIT 1000
  )

SELECT
  fv.UserId,
  fv.DisplayName,
  fv.Reputation,
  fv.PostTitle,
  fv.PostScore,
  fv.NetVoteScore,
  fv.ViewCount,
  fv.Status,
  fv.Rank,
  fv.TagName,
  fv.QCount,
  st.Category,
  st.Total
FROM final_view fv
LEFT JOIN status_totals st ON st.Category = fv.Status
ORDER BY fv.Reputation DESC, fv.PostScore DESC;