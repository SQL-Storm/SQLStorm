-- {"query": "631.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3322}
WITH
q_posts AS (
  SELECT p.Id AS QuestionId,
         p.CreationDate AS QCreationDate,
         p.Title,
         p.Tags,
         p.OwnerUserId AS QOwnerId,
         p.Score AS QScore,
         p.ViewCount,
         p.AcceptedAnswerId,
         COALESCE(p.AnswerCount, 0) AS AnswerCount,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
  FROM Posts p
  WHERE p.PostTypeId = 1
),
a_posts AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId AS AOwnerId,
         a.Score AS AScore,
         a.CreationDate AS ACreationDate
  FROM Posts a
  WHERE a.PostTypeId = 2
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views AS ProfileViews,
         u.CreationDate AS UCreationDate,
         COALESCE(NULLIF(TRIM(COALESCE(u.Location,'')),''),
                  'Unknown') AS NormLocation,
         CAST(date_part('year', age(CAST('2024-10-01 12:34:56' AS timestamp), u.CreationDate)) AS int) AS AccountAgeYears
  FROM Users u
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCnt,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCnt,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCnt,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyStarted,
         SUM(CASE WHEN v.VoteTypeId = 9 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyAwarded,
         MIN(v.CreationDate) AS FirstVoteAt,
         MAX(v.CreationDate) AS LastVoteAt
  FROM Votes v
  GROUP BY v.PostId
),
comment_agg AS (
  SELECT c.PostId,
         COUNT(*) AS CommentCnt,
         SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PosComments,
         MAX(c.CreationDate) AS LastCommentAt
  FROM Comments c
  GROUP BY c.PostId
),
tag_expand AS (
  SELECT p.Id AS PostId,
         unnest(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><')) AS TagName
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
tag_rank AS (
  SELECT te.PostId,
         te.TagName,
         t.Count AS TagGlobalCount,
         row_number() OVER (PARTITION BY te.PostId ORDER BY t.Count DESC NULLS LAST, te.TagName) AS TagRankByGlobal
  FROM tag_expand te
  LEFT JOIN Tags t ON lower(t.TagName) = lower(te.TagName)
),
best_tag AS (
  SELECT PostId,
         TagName AS DominantTag,
         TagGlobalCount
  FROM tag_rank
  WHERE TagRankByGlobal = 1
),
edits AS (
  SELECT ph.PostId,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCnt,
         MAX(ph.CreationDate) AS LastEditAt,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteEvents,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenEvents,
         SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+' THEN 1 ELSE 0 END) AS CloseReasonsLogged
  FROM PostHistory ph
  GROUP BY ph.PostId
),
dup_links AS (
  SELECT pl.PostId,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedLinks,
         MIN(pl.CreationDate) AS FirstLinkAt
  FROM PostLinks pl
  GROUP BY pl.PostId
),
accepted_answer AS (
  SELECT a.QuestionId,
         a.AnswerId AS AcceptedAnswerId,
         a.AOwnerId AS AcceptedOwnerId,
         a.AScore AS AcceptedScore,
         a.ACreationDate AS AcceptedAt
  FROM a_posts a
  JOIN q_posts q ON q.AcceptedAnswerId = a.AnswerId
),
answerers AS (
  SELECT a.QuestionId,
         COUNT(*) AS AnswererCnt,
         COUNT(DISTINCT a.AOwnerId) AS DistinctAnswerers,
         MAX(a.AScore) AS MaxAnswerScore,
         MIN(a.ACreationDate) AS FirstAnswerAt
  FROM a_posts a
  GROUP BY a.QuestionId
),
q_activity AS (
  SELECT q.QuestionId,
         q.QCreationDate,
         greatest(
           COALESCE(q.QCreationDate, timestamp 'epoch'),
           COALESCE(v.FirstVoteAt, timestamp 'epoch'),
           COALESCE(v.LastVoteAt, timestamp 'epoch'),
           COALESCE(c.LastCommentAt, timestamp 'epoch'),
           COALESCE(e.LastEditAt, timestamp 'epoch')
         ) AS LastActivityDerived
  FROM q_posts q
  LEFT JOIN votes_agg v ON v.PostId = q.QuestionId
  LEFT JOIN comment_agg c ON c.PostId = q.QuestionId
  LEFT JOIN edits e ON e.PostId = q.QuestionId
),
owner_enriched AS (
  SELECT q.QuestionId,
         u.UserId AS QOwnerId,
         u.Reputation AS OwnerReputation,
         u.AccountAgeYears,
         u.NormLocation,
         (u.UpVotes - u.DownVotes) AS OwnerNetVotes,
         CASE WHEN u.ProfileViews IS NULL OR u.ProfileViews = 0 THEN NULL ELSE (CAST(u.Reputation AS numeric) / NULLIF(u.ProfileViews,0)) END AS RepPerProfileView
  FROM q_posts q
  LEFT JOIN user_stats u ON u.UserId = q.QOwnerId
),
rankings AS (
  SELECT
    q.QuestionId,
    q.QScore,
    q.ViewCount,
    a.AnswererCnt,
    COALESCE(v.UpvoteCnt,0) AS UpvoteCnt,
    COALESCE(v.DownvoteCnt,0) AS DownvoteCnt,
    COALESCE(v.FavoriteCnt,0) AS FavoriteCnt,
    COALESCE(v.BountyStarted,0) AS BountyStarted,
    COALESCE(v.BountyAwarded,0) AS BountyAwarded,
    COALESCE(c.CommentCnt,0) AS CommentCnt,
    COALESCE(e.EditCnt,0) AS EditCnt,
    COALESCE(d.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(d.LinkedLinks,0) AS LinkedLinks,
    dense_rank() OVER (ORDER BY q.QScore DESC NULLS LAST, COALESCE(v.UpvoteCnt,0) DESC, COALESCE(v.FavoriteCnt,0) DESC) AS RankByScore,
    dense_rank() OVER (ORDER BY COALESCE(v.FavoriteCnt,0) DESC, q.ViewCount DESC NULLS LAST) AS RankByFav,
    dense_rank() OVER (ORDER BY (COALESCE(v.UpvoteCnt,0) - COALESCE(v.DownvoteCnt,0)) DESC) AS RankByNetVotes,
    ntile(100) OVER (ORDER BY q.ViewCount DESC NULLS LAST) AS ViewPercentile
  FROM q_posts q
  LEFT JOIN votes_agg v ON v.PostId = q.QuestionId
  LEFT JOIN comment_agg c ON c.PostId = q.QuestionId
  LEFT JOIN edits e ON e.PostId = q.QuestionId
  LEFT JOIN dup_links d ON d.PostId = q.QuestionId
  LEFT JOIN answerers a ON a.QuestionId = q.QuestionId
),
quality_flags AS (
  SELECT
    r.QuestionId,
    CASE WHEN r.QScore >= 10 AND r.ViewCount >= 1000 AND r.FavoriteCnt >= 5 THEN 1 ELSE 0 END AS IsPopular,
    CASE WHEN r.EditCnt >= 5 OR r.CommentCnt >= 20 THEN 1 ELSE 0 END AS IsContentious,
    CASE WHEN r.DuplicateLinks > 0 THEN 1 ELSE 0 END AS IsDuplicateLinked,
    CASE WHEN r.BountyAwarded > 0 THEN 1 ELSE 0 END AS HasBountyHistory,
    CASE WHEN r.ViewPercentile >= 95 THEN 1 ELSE 0 END AS IsTop5PctViews
  FROM rankings r
),
null_stress AS (
  SELECT
    q.QuestionId,
    NULLIF(b.DominantTag, '') AS DominantTag,
    COALESCE(b.TagGlobalCount, 0) AS DominantTagGlobalCount,
    COALESCE(a.AcceptedAnswerId, q.AcceptedAnswerId) AS AcceptedAnswerIdCoalesced,
    CASE WHEN q.AcceptedAnswerId IS NULL AND a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS AcceptedIdFilledFromJoin,
    COALESCE(o.NormLocation, 'Unknown') AS SafeLocation,
    COALESCE(o.RepPerProfileView, 0.0) AS SafeRepPerView
  FROM q_posts q
  LEFT JOIN best_tag b ON b.PostId = q.QuestionId
  LEFT JOIN accepted_answer a ON a.QuestionId = q.QuestionId
  LEFT JOIN owner_enriched o ON o.QuestionId = q.QuestionId
),
cross_user_compare AS (
  SELECT
    q.QuestionId,
    o.OwnerReputation,
    (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY us.Reputation)
     FROM user_stats us) AS GlobalMedianRep,
    (SELECT AVG(us.Reputation) FROM user_stats us) AS GlobalAvgRep
  FROM owner_enriched o
  JOIN q_posts q ON q.QuestionId = o.QuestionId
),
final_scores AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.Tags,
    o.OwnerReputation,
    o.AccountAgeYears,
    o.OwnerNetVotes,
    ns.DominantTag,
    ns.DominantTagGlobalCount,
    ns.SafeLocation,
    r.QScore,
    r.ViewCount,
    r.UpvoteCnt,
    r.DownvoteCnt,
    r.FavoriteCnt,
    r.BountyStarted,
    r.BountyAwarded,
    r.CommentCnt,
    r.EditCnt,
    r.DuplicateLinks,
    r.LinkedLinks,
    r.RankByScore,
    r.RankByFav,
    r.RankByNetVotes,
    r.ViewPercentile,
    e.CloseVoteEvents,
    e.ReopenEvents,
    qact.LastActivityDerived,
    qa.AcceptedAnswerId,
    ac.AcceptedScore AS AcceptedAnswerScore,
    ac.AcceptedAt AS AcceptedAnswerAt,
    COALESCE(qa.AcceptedAnswerId, ns.AcceptedAnswerIdCoalesced) AS AnyAcceptedAnswerId,
    q.IsClosed,
    q.AnswerCount,
    af.AnswererCnt,
    af.DistinctAnswerers,
    af.MaxAnswerScore,
    af.FirstAnswerAt,
    qlt.IsPopular,
    qlt.IsContentious,
    qlt.IsDuplicateLinked,
    qlt.HasBountyHistory,
    qlt.IsTop5PctViews,
    CAST(
      (
        COALESCE(r.QScore,0)*3
        + greatest(COALESCE(r.UpvoteCnt,0) - COALESCE(r.DownvoteCnt,0), 0)*2
        + COALESCE(r.FavoriteCnt,0)*4
        + least(COALESCE(r.ViewPercentile,0), 100)*0.5
        + CASE WHEN qlt.HasBountyHistory=1 THEN 10 ELSE 0 END
        + CASE WHEN qa.AcceptedAnswerId IS NOT NULL THEN 8 ELSE 0 END
        - COALESCE(r.DuplicateLinks,0)*5
        - CASE WHEN q.IsClosed=1 THEN 7 ELSE 0 END
      ) AS numeric(18,2)
    ) AS CompositeScore
  FROM q_posts q
  LEFT JOIN owner_enriched o ON o.QuestionId = q.QuestionId
  LEFT JOIN rankings r ON r.QuestionId = q.QuestionId
  LEFT JOIN edits e ON e.PostId = q.QuestionId
  LEFT JOIN q_activity qact ON qact.QuestionId = q.QuestionId
  LEFT JOIN accepted_answer qa ON qa.QuestionId = q.QuestionId
  LEFT JOIN accepted_answer ac ON ac.QuestionId = q.QuestionId
  LEFT JOIN answerers af ON af.QuestionId = q.QuestionId
  LEFT JOIN null_stress ns ON ns.QuestionId = q.QuestionId
  LEFT JOIN quality_flags qlt ON qlt.QuestionId = q.QuestionId
),
synth AS (
  SELECT
    fs.QuestionId,
    fs.Title,
    fs.Tags,
    fs.OwnerReputation,
    fs.AccountAgeYears,
    fs.OwnerNetVotes,
    fs.DominantTag,
    fs.DominantTagGlobalCount,
    fs.SafeLocation,
    fs.QScore,
    fs.ViewCount,
    fs.UpvoteCnt,
    fs.DownvoteCnt,
    fs.FavoriteCnt,
    fs.BountyStarted,
    fs.BountyAwarded,
    fs.CommentCnt,
    fs.EditCnt,
    fs.DuplicateLinks,
    fs.LinkedLinks,
    fs.RankByScore,
    fs.RankByFav,
    fs.RankByNetVotes,
    fs.ViewPercentile,
    fs.CloseVoteEvents,
    fs.ReopenEvents,
    fs.LastActivityDerived,
    fs.AcceptedAnswerId,
    fs.AcceptedAnswerScore,
    fs.AcceptedAnswerAt,
    fs.AnyAcceptedAnswerId,
    fs.IsClosed,
    fs.AnswerCount,
    fs.AnswererCnt,
    fs.DistinctAnswerers,
    fs.MaxAnswerScore,
    fs.FirstAnswerAt,
    fs.IsPopular,
    fs.IsContentious,
    fs.IsDuplicateLinked,
    fs.HasBountyHistory,
    fs.IsTop5PctViews,
    fs.CompositeScore,
    CASE
      WHEN fs.SafeLocation ILIKE '%united states%' OR fs.SafeLocation ILIKE '%usa%' THEN 'US'
      WHEN fs.SafeLocation ILIKE '%india%' THEN 'IN'
      WHEN fs.SafeLocation ILIKE '%united kingdom%' OR fs.SafeLocation ILIKE '%uk%' THEN 'UK'
      WHEN fs.SafeLocation ILIKE '%germany%' THEN 'DE'
      WHEN fs.SafeLocation = 'Unknown' THEN 'UNK'
      ELSE 'OTHER'
    END AS CountryBucket,
    row_number() OVER (ORDER BY fs.CompositeScore DESC NULLS LAST, fs.ViewCount DESC NULLS LAST) AS GlobalRowNum,
    SUM(CASE WHEN fs.IsClosed=1 THEN 1 ELSE 0 END) OVER (
      ORDER BY fs.CompositeScore DESC NULLS LAST
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RunningClosedCount
  FROM final_scores fs
)
SELECT
  s.QuestionId,
  COALESCE(NULLIF(s.Title,''), '[no title]') AS Title,
  s.DominantTag,
  s.DominantTagGlobalCount,
  s.OwnerReputation,
  s.AccountAgeYears,
  s.OwnerNetVotes,
  s.SafeLocation,
  s.CountryBucket,
  s.QScore,
  s.ViewCount,
  s.UpvoteCnt,
  s.DownvoteCnt,
  s.FavoriteCnt,
  s.BountyStarted,
  s.BountyAwarded,
  s.CommentCnt,
  s.EditCnt,
  s.DuplicateLinks,
  s.LinkedLinks,
  s.RankByScore,
  s.RankByFav,
  s.RankByNetVotes,
  s.ViewPercentile,
  s.CloseVoteEvents,
  s.ReopenEvents,
  s.LastActivityDerived,
  s.AcceptedAnswerId,
  s.AcceptedAnswerScore,
  s.AcceptedAnswerAt,
  s.AnyAcceptedAnswerId,
  s.IsClosed,
  s.AnswerCount,
  s.AnswererCnt,
  s.DistinctAnswerers,
  s.MaxAnswerScore,
  s.FirstAnswerAt,
  s.IsPopular,
  s.IsContentious,
  s.IsDuplicateLinked,
  s.HasBountyHistory,
  s.IsTop5PctViews,
  s.CompositeScore,
  s.GlobalRowNum,
  s.RunningClosedCount
FROM synth s
WHERE
  (
    s.CompositeScore > (
      SELECT AVG(CompositeScore) FROM synth
    )
    OR s.IsTop5PctViews = 1
  )
  AND (
    s.DominantTag IS NULL
    OR (
      lower(s.DominantTag) NOT LIKE 'meta'
      AND lower(s.DominantTag) NOT LIKE 'discussion'
      AND lower(s.DominantTag) NOT LIKE 'off-topic'
    )
  )
ORDER BY s.CompositeScore DESC NULLS LAST, s.ViewCount DESC NULLS LAST
LIMIT 500;