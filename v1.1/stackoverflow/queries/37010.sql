WITH
QuestionBase AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.Tags,
    COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
    CASE
      WHEN p.Tags IS NULL THEN ARRAY[]::text[] -- keep array literal cast for dialects that support it; if not supported, engines will need alternative
      ELSE string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')
    END AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
    AND p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
AnswerBase AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.CreationDate AS AnswerCreation,
    a.Score AS AnswerScore,
    a.OwnerUserId AS AnswerOwner,
    (a.Body IS NOT NULL) AS HasBody
  FROM Posts a
  WHERE a.PostTypeId = 2
),
AnswerAgg AS (
  SELECT
    q.QuestionId,
    COUNT(a.AnswerId) AS AnswersTotal,
    SUM(CASE WHEN a.AnswerScore > 0 THEN 1 ELSE 0 END) AS PositiveAnswers,
    AVG(a.AnswerScore) AS AvgAnswerScore,
    MIN(a.AnswerCreation) AS FirstAnswerDate,
    MAX(a.AnswerCreation) AS LastAnswerDate
  FROM QuestionBase q
  LEFT JOIN AnswerBase a ON a.QuestionId = q.QuestionId
  GROUP BY q.QuestionId
),
RecentVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN vt.Name = 'Favorite' OR vt.Name = 'Save' THEN 1 ELSE 0 END) AS Favorites,
    MIN(v.CreationDate) AS FirstVoteAt,
    MAX(v.CreationDate) AS LastVoteAt
  FROM Votes v
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  GROUP BY v.PostId
),
TagExplode AS (
  SELECT
    q.QuestionId,
    UNNEST(q.TagArray) AS Tag
  FROM QuestionBase q
),
TagStats AS (
  SELECT
    te.Tag AS Tag,
    COUNT(DISTINCT te.QuestionId) AS QuestionsWithTag,
    SUM(qb.ViewCount) AS TotalViews,
    AVG(qb.Score) AS AvgQuestionScore,
    SUM(CASE WHEN qb.AnswerCount > 0 THEN 1 ELSE 0 END) AS QuestionsWithAnswers
  FROM TagExplode te
  JOIN QuestionBase qb ON qb.QuestionId = te.QuestionId
  GROUP BY te.Tag
  ORDER BY QuestionsWithTag DESC
),
PostLinkAgg AS (
  SELECT
    pl.PostId AS QuestionId,
    SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS LinkedCount,
    SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCount,
    COUNT(*) AS TotalLinks
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
HistoryAgg AS (
  SELECT
    ph.PostId,
    COUNT(*) AS Revisions,
    COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS DistinctEditors,
    MAX(ph.CreationDate) AS LastRevisionDate
  FROM PostHistory ph
  WHERE ph.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  GROUP BY ph.PostId
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
    COUNT(b.Id) AS BadgesEarned,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation >= 10000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
  ORDER BY u.Reputation DESC
  LIMIT 250
),
QuestionScore AS (
  SELECT
    qb.QuestionId,
    qb.Title,
    qb.CreationDate,
    qb.LastActivityDate,
    qb.ViewCount,
    qb.Score,
    qb.AnswerCount,
    COALESCE(aa.AnswersTotal,0) AS AnswersTotal,
    COALESCE(aa.PositiveAnswers,0) AS PositiveAnswers,
    COALESCE(rv.UpVotes,0) AS RecentUpVotes,
    COALESCE(rv.DownVotes,0) AS RecentDownVotes,
    COALESCE(pl.LinkedCount,0) AS LinkedCount,
    COALESCE(pl.DuplicateCount,0) AS DuplicateCount,
    COALESCE(ha.Revisions,0) AS Revisions,
    COALESCE(ha.DistinctEditors,0) AS DistinctEditors,
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qb.CreationDate))/86400.0) AS AgeDays,
    (
      (COALESCE(rv.UpVotes,0) - COALESCE(rv.DownVotes,0)) * 2.5
      + (qb.ViewCount / NULLIF(GREATEST(1, EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qb.CreationDate))/86400.0),0)) * 0.05
      + COALESCE(aa.PositiveAnswers,0) * 3
      + GREATEST(0, 10 - (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qb.LastActivityDate))/86400.0)/30) * 5
      - COALESCE(pl.DuplicateCount,0) * 2
      + LEAST(ha.DistinctEditors,5) * 1.2
    ) AS HeatScore,
    qb.OwnerUserId
  FROM QuestionBase qb
  LEFT JOIN AnswerAgg aa ON aa.QuestionId = qb.QuestionId
  LEFT JOIN RecentVotes rv ON rv.PostId = qb.QuestionId
  LEFT JOIN PostLinkAgg pl ON pl.QuestionId = qb.QuestionId
  LEFT JOIN HistoryAgg ha ON ha.PostId = qb.QuestionId
),
QuestionTagHotness AS (
  SELECT
    q.QuestionId,
    q.Tag,
    ts.QuestionsWithTag,
    ts.TotalViews,
    ts.AvgQuestionScore,
    (CAST(ts.QuestionsWithTag AS numeric) / NULLIF((SELECT MAX(QuestionsWithTag) FROM TagStats),0)) AS TagPopularityNorm,
    ROW_NUMBER() OVER (PARTITION BY q.QuestionId ORDER BY ts.QuestionsWithTag DESC NULLS LAST) AS TagRank
  FROM TagExplode q
  LEFT JOIN TagStats ts ON ts.Tag = q.Tag
),
FinalAssembly AS (
  SELECT
    qs.QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.LastActivityDate,
    qs.ViewCount,
    qs.Score,
    qs.AnswerCount,
    qs.AnswersTotal,
    qs.PositiveAnswers,
    qs.RecentUpVotes,
    qs.RecentDownVotes,
    qs.LinkedCount,
    qs.DuplicateCount,
    qs.Revisions,
    qs.DistinctEditors,
    qs.AgeDays,
    qs.HeatScore,
    qs.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    qt.Tag AS TopTag,
    qt.TagPopularityNorm,
    qt.QuestionsWithTag,
    qt.TotalViews AS TagTotalViews
  FROM QuestionScore qs
  LEFT JOIN Users u ON u.Id = qs.OwnerUserId
  LEFT JOIN (
    SELECT QuestionId, Tag, TagPopularityNorm, QuestionsWithTag, TotalViews
    FROM QuestionTagHotness
    WHERE TagRank = 1
  ) qt ON qt.QuestionId = qs.QuestionId
)
SELECT
  fa.QuestionId,
  fa.Title,
  fa.OwnerDisplayName,
  fa.OwnerReputation,
  fa.TopTag,
  fa.TagPopularityNorm,
  fa.ViewCount,
  fa.Score,
  fa.AnswerCount,
  fa.AnswersTotal,
  fa.PositiveAnswers,
  fa.RecentUpVotes,
  fa.RecentDownVotes,
  fa.LinkedCount,
  fa.DuplicateCount,
  fa.Revisions,
  fa.DistinctEditors,
  ROUND(fa.AgeDays,2) AS AgeDays,
  ROUND(CAST(fa.HeatScore AS numeric),4) AS HeatScore,
  NTILE(10) OVER (ORDER BY fa.HeatScore DESC) AS HeatDecile,
  RANK() OVER (ORDER BY fa.HeatScore DESC, fa.ViewCount DESC) AS HeatRank,
  PERCENT_RANK() OVER (ORDER BY fa.HeatScore DESC) AS HeatPercentile,
  COALESCE((
    SELECT AVG(f2.HeatScore)
    FROM FinalAssembly f2
    WHERE f2.TopTag = fa.TopTag
      AND f2.QuestionId <> fa.QuestionId
      AND f2.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
  ), 0) AS AvgHeatForTag,
  COALESCE((
    SELECT COUNT(DISTINCT a.OwnerUserId)
    FROM Posts a
    WHERE a.ParentId = fa.QuestionId
      AND a.PostTypeId = 2
      AND a.OwnerUserId IN (SELECT UserId FROM TopUsers)
  ), 0) AS TopUserAnswers,
  COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = fa.QuestionId AND c.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')),0) AS RecentComments,
  fa.CreationDate,
  fa.LastActivityDate
FROM FinalAssembly fa
WHERE fa.HeatScore IS NOT NULL
ORDER BY fa.HeatScore DESC NULLS LAST, fa.ViewCount DESC NULLS LAST
LIMIT 100;