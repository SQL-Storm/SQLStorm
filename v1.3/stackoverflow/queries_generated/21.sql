-- {"query": "21.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2653} 
WITH
-- recent activity per post including last comment and last history
post_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(cmax.LastCommentDate, phmax.LastHistoryDate, p.LastActivityDate) AS EffectiveLastActivity,
    cmax.LastCommentText,
    phmax.LastHistoryTypeId
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS LastCommentDate, MAX(Text) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LastCommentText
    FROM Comments
    GROUP BY PostId
  ) cmax ON cmax.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS LastHistoryDate, MAX(PostHistoryTypeId) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LastHistoryTypeId
    FROM PostHistory
    GROUP BY PostId
  ) phmax ON phmax.PostId = p.Id
),
-- compute tag array and exploded tags
tag_explode AS (
  SELECT
    pa.*,
    CASE WHEN pa.Tags IS NULL OR LENGTH(TRIM(pa.Tags)) = 0 THEN ARRAY[]::varchar[] 
         ELSE string_to_array(substring(pa.Tags, 2, length(pa.Tags)-2), '><') END AS TagArray
  FROM post_activity pa
),
exploded_tags AS (
  SELECT
    te.*,
    tag AS Tag
  FROM tag_explode te
  LEFT JOIN LATERAL (
    SELECT unnest(te.TagArray) AS tag
  ) u ON true
),
-- user aggregates
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
    AVG(p.Score) FILTER (WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
    MAX(p.CreationDate) FILTER (WHERE p.OwnerUserId = u.Id) AS LastPostDate,
    COUNT(b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- ranking answers by score within their question
answer_ranks AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId AS AnswererId,
    a.Score AS AnswerScore,
    RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate DESC) AS RecentAnswerRow
  FROM Posts a
  WHERE a.PostTypeId = 2
),
-- correlated metrics: duplicate links and cross-post references
post_links_agg AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE lt.Name = 'Duplicate' OR pl.LinkTypeId = 3) AS DuplicateLinks,
    COUNT(*) FILTER (WHERE lt.Name = 'Linked' OR pl.LinkTypeId = 1) AS OutgoingLinks,
    COUNT(DISTINCT pl.RelatedPostId) AS DistinctRelated
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
-- votes breakout
vote_summary AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE vt.Name = 'UpMod' OR v.VoteTypeId = 2) AS UpVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'DownMod' OR v.VoteTypeId = 3) AS DownVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'Favorite' OR v.VoteTypeId = 5) AS Favorites,
    COUNT(*) FILTER (WHERE vt.Name = 'BountyStart' OR v.VoteTypeId = 8) AS BountiesStarted,
    SUM(v.BountyAmount) AS TotalBountyAmount
  FROM Votes v
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.PostId
),
-- compute complex score metric mixing various signals
complex_scores AS (
  SELECT
    et.PostId,
    et.PostTypeId,
    et.ParentId,
    et.OwnerUserId,
    et.Title,
    et.Tag,
    COALESCE(vs.UpVotes,0) AS UpVotes,
    COALESCE(vs.DownVotes,0) AS DownVotes,
    COALESCE(pl.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(pl.OutgoingLinks,0) AS OutgoingLinks,
    COALESCE(us.Reputation, 0) AS OwnerReputation,
    COALESCE(us.GoldBadges,0) AS OwnerGold,
    COALESCE(us.SilverBadges,0) AS OwnerSilver,
    COALESCE(us.BronzeBadges,0) AS OwnerBronze,
    et.Score,
    et.ViewCount,
    et.EffectiveLastActivity,
    -- composite score with non-linear transforms and null-aware math
    (COALESCE(et.Score,0) * 1.5
     + LOG(GREATEST(1, COALESCE(et.ViewCount,0))) * 0.75
     + (COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0)) * 2.0
     + LEAST(20, COALESCE(us.Reputation,0) / 1000.0) * 3.0
     + (CASE WHEN COALESCE(pl.DuplicateLinks,0) > 0 THEN -5 ELSE 0 END)
     + (CASE WHEN et.PostTypeId = 1 THEN 10 ELSE 0 END)
    ) * (1 + COALESCE(us.GoldBadges,0)*0.02) AS CompositeScoreRaw,
    -- string derived feature: snippet of title + tag
    LEFT(CONCAT(COALESCE(et.Title,''), ' | ', COALESCE(et.Tag,'')), 120) AS TitleTagSnippet
  FROM exploded_tags et
  LEFT JOIN vote_summary vs ON vs.PostId = et.PostId
  LEFT JOIN post_links_agg pl ON pl.PostId = et.PostId
  LEFT JOIN Users us ON us.Id = et.OwnerUserId
),
-- normalize composite scores and detect outliers
score_norm AS (
  SELECT
    cs.*,
    AVG(CompositeScoreRaw) OVER () AS MeanScore,
    STDDEV_POP(CompositeScoreRaw) OVER () AS StddevScore
  FROM complex_scores cs
),
-- pick top answers per question and correlate with accepted answer
top_answer_pairs AS (
  SELECT
    q.Id AS QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate AS QCreation,
    a.Id AS AnswerId,
    a.OwnerUserId AS AnswererId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreation,
    ar.ScoreRank,
    CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
    COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0) AS NetVotes,
    ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY ar.ScoreRank, a.Score DESC NULLS LAST) AS RankWithinQuestion
  FROM Posts q
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN answer_ranks ar ON ar.AnswerId = a.Id
  LEFT JOIN vote_summary vs ON vs.PostId = a.Id
  WHERE q.PostTypeId = 1
),
-- final selection combining many pieces and exercising complex predicates
final_selection AS (
  SELECT
    sn.PostId,
    sn.PostTypeId,
    sn.ParentId,
    sn.TitleTagSnippet,
    sn.Tag,
    sn.CompositeScoreRaw,
    (sn.CompositeScoreRaw - sn.MeanScore) / NULLIF(sn.StddevScore,0) AS ZScore,
    us.DisplayName AS OwnerName,
    us.Reputation AS OwnerReputation,
    COALESCE(pl.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(vs.UpVotes,0) AS UpVotes,
    COALESCE(vs.DownVotes,0) AS DownVotes,
    COALESCE(vs.Favorites,0) AS Favorites,
    CASE
      WHEN sn.PostTypeId = 1 THEN 'Question'
      WHEN sn.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    -- detect stale unanswered questions: question older than 60 days with no answers and low activity
    CASE WHEN sn.PostTypeId = 1 AND COALESCE(sn.CompositeScoreRaw,0) < (sn.MeanScore - sn.StddevScore) AND NOT EXISTS (
      SELECT 1 FROM Posts a WHERE a.ParentId = sn.PostId AND a.PostTypeId = 2
    ) AND sn.EffectiveLastActivity < NOW() - INTERVAL '60 days' THEN 1 ELSE 0 END AS IsStaleLowScoringQuestion,
    -- pattern match in tags (complex string predicate) and null logic
    CASE WHEN sn.Tag IS NOT NULL AND LOWER(sn.Tag) LIKE ANY (ARRAY['%sql%','%performance%','%benchmark%','%indexing%']) THEN 1 ELSE 0 END AS IsPerfTag,
    -- correlated subquery: recent activity by high-rep users on same tag
    (SELECT COUNT(DISTINCT p2.OwnerUserId)
     FROM Posts p2
     WHERE p2.PostTypeId = 1
       AND p2.Tags LIKE CONCAT('%<', sn.Tag, '>%')
       AND p2.CreationDate > NOW() - INTERVAL '365 days'
       AND p2.OwnerUserId IS NOT NULL
       AND (SELECT Reputation FROM Users u2 WHERE u2.Id = p2.OwnerUserId) > 5000
    ) AS HighRepAuthorsInTagPastYear
  FROM score_norm sn
  LEFT JOIN Users us ON us.Id = sn.OwnerUserId
  LEFT JOIN post_links_agg pl ON pl.PostId = sn.PostId
  LEFT JOIN vote_summary vs ON vs.PostId = sn.PostId
)
SELECT
  fs.*,
  -- join with top answer info when this row is a question
  tap.AnswerId AS TopAnswerId,
  tap.AnswerScore AS TopAnswerScore,
  tap.IsAccepted AS TopAnswerAccepted,
  tsa.RankWithinQuestion AS TopAnswerRank
FROM final_selection fs
LEFT JOIN LATERAL (
  SELECT *
  FROM top_answer_pairs tap
  WHERE tap.QuestionId = fs.PostId
  ORDER BY tap.IsAccepted DESC, tap.AnswerScore DESC NULLS LAST, tap.RankWithinQuestion ASC
  LIMIT 1
) tap ON fs.PostTypeId = 1
LEFT JOIN LATERAL (
  SELECT RankWithinQuestion
  FROM top_answer_pairs tsa
  WHERE tsa.QuestionId = fs.PostId AND tsa.AnswerId = tap.AnswerId
) tsa ON true
WHERE
  -- stress-test complex predicates: include items with unusual null combos or extreme normalized scores
  (
    fs.ZScore IS NULL
    OR fs.ZScore > 2.5
    OR fs.ZScore < -2.5
    OR fs.IsStaleLowScoringQuestion = 1
    OR fs.IsPerfTag = 1
    OR fs.HighRepAuthorsInTagPastYear > 10
  )
ORDER BY
  COALESCE(fs.ZScore, -999) DESC,
  fs.CompositeScoreRaw DESC NULLS LAST,
  fs.PostId
LIMIT 100;