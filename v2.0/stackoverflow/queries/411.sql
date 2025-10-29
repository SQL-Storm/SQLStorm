with
q_posts as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreation,
    p.OwnerUserId as QuestionOwnerId,
    p.Score as QuestionScore,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName) as QuestionOwnerName,
    u.Reputation as QuestionOwnerRep
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
a_posts as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.CreationDate as AnswerCreation,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    coalesce(nullif(trim(a.OwnerDisplayName), ''), ua.DisplayName) as AnswerOwnerName,
    ua.Reputation as AnswerOwnerRep,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_best_by_score
  from Posts a
  left join Users ua on ua.Id = a.OwnerUserId
  where a.PostTypeId = 2
),
answers_ranked as (
  select
    ap.*,
    dense_rank() over (partition by ap.QuestionId order by ap.AnswerScore desc) as dr_answer_score
  from a_posts ap
),
accepted_vs_best as (
  select
    q.QuestionId,
    q.AcceptedAnswerId,
    ar.AnswerId,
    ar.AnswerScore,
    ar.AnswerCreation,
    ar.AnswerOwnerId,
    ar.AnswerOwnerRep,
    ar.rn_best_by_score,
    case when q.AcceptedAnswerId is not null and q.AcceptedAnswerId = ar.AnswerId then 1 else 0 end as IsAccepted,
    min(case when q.AcceptedAnswerId is not null and q.AcceptedAnswerId = ar.AnswerId then ar.AnswerScore end) over (partition by q.QuestionId) as AcceptedScore,
    min(case when ar.rn_best_by_score = 1 then ar.AnswerScore end) over (partition by q.QuestionId) as TopScore
  from q_posts q
  left join answers_ranked ar on ar.QuestionId = q.QuestionId
),
badge_summary as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
    sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
    count(*) as TotalBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    min(v.CreationDate) as FirstVoteAt,
    max(v.CreationDate) as LastVoteAt
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    avg(case when c.Score <> 0 then c.Score end) as AvgNonZeroCommentScore,
    string_agg(substring(coalesce(c.UserDisplayName, ''), 1, 20), '|' order by c.Score desc NULLS LAST, c.CreationDate) as TopCommenters
  from Comments c
  group by c.PostId
),
links_agg as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount,
    count(*) as TotalLinks,
    min(pl.CreationDate) as FirstLinkAt,
    max(pl.CreationDate) as LastLinkAt
  from PostLinks pl
  group by pl.PostId
),
history_flags as (
  select
    ph.PostId,
    max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as WasClosed,
    max(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as WasReopened,
    max(case when ph.PostHistoryTypeId = 12 then 1 else 0 end) as WasDeleted,
    max(case when ph.PostHistoryTypeId = 13 then 1 else 0 end) as WasUndeleted,
    max(case when ph.PostHistoryTypeId in (33,34) then 1 else 0 end) as HasPostNotice,
    max(case when ph.PostHistoryTypeId in (35,36) then 1 else 0 end) as WasMigrated,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11,12,13,35,36)) as FirstModEventAt
  from PostHistory ph
  group by ph.PostId
),
question_tags as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
  from q_posts q
  where q.Tags is not null and length(q.Tags) > 2
),
tag_activity as (
  select
    qt.tag,
    count(distinct qt.QuestionId) as QuestionsWithTag
  from question_tags qt
  group by qt.tag
),
owner_activity as (
  select
    q.QuestionOwnerId as UserId,
    count(*) as QuestionsAsked,
    sum(q.ViewCount) as TotalViews,
    avg(q.QuestionScore) as AvgQScore,
    min(q.QuestionCreation) as FirstQAt,
    max(q.QuestionCreation) as LastQAt
  from q_posts q
  where q.QuestionOwnerId is not null
  group by q.QuestionOwnerId
),
time_bins as (
  select
    q.QuestionId,
    date_trunc('month', q.QuestionCreation) as month_bucket
  from q_posts q
),
q_metrics as (
  select
    q.QuestionId,
    q.Title,
    q.Tags,
    q.QuestionScore,
    q.ViewCount,
    q.QuestionCreation,
    q.QuestionOwnerId,
    q.QuestionOwnerName,
    q.QuestionOwnerRep,
    va.UpVotes,
    va.DownVotes,
    va.Favorites,
    va.BountyTotal,
    ca.CommentCount,
    ca.MaxCommentScore,
    ca.AvgNonZeroCommentScore,
    la.LinkedCount,
    la.DuplicateCount,
    la.TotalLinks,
    hf.WasClosed,
    hf.WasReopened,
    hf.WasDeleted,
    hf.WasUndeleted,
    hf.HasPostNotice,
    hf.WasMigrated
  from q_posts q
  left join votes_agg va on va.PostId = q.QuestionId
  left join comments_agg ca on ca.PostId = q.QuestionId
  left join links_agg la on la.PostId = q.QuestionId
  left join history_flags hf on hf.PostId = q.QuestionId
),
acceptance_metrics as (
  select
    avb.QuestionId,
    max(avb.IsAccepted) as HasAcceptedAnswer,
    min(case when avb.IsAccepted = 1 then avb.AnswerCreation end) as AcceptedAt,
    max(avb.AcceptedScore) as AcceptedAnswerScore,
    max(avb.TopScore) as TopAnswerScore,
    max(case when avb.rn_best_by_score = 1 then avb.AnswerId end) as TopAnswerId,
    max(case when avb.rn_best_by_score = 1 then avb.AnswerOwnerId end) as TopAnswerOwnerId
  from accepted_vs_best avb
  group by avb.QuestionId
),
answerer_badge_mix as (
  select
    am.QuestionId,
    coalesce(bs_g.GoldCount,0) as TopAnsGold,
    coalesce(bs_s.SilverCount,0) as TopAnsSilver,
    coalesce(bs_b.BronzeCount,0) as TopAnsBronze
  from acceptance_metrics am
  left join badge_summary bs_g on bs_g.UserId = am.TopAnswerOwnerId
  left join badge_summary bs_s on bs_s.UserId = am.TopAnswerOwnerId
  left join badge_summary bs_b on bs_b.UserId = am.TopAnswerOwnerId
),
owner_badge_mix as (
  select
    q.QuestionId,
    coalesce(bs.TotalBadges,0) as OwnerTotalBadges,
    coalesce(bs.TagBadges,0) as OwnerTagBadges
  from q_posts q
  left join badge_summary bs on bs.UserId = q.QuestionOwnerId
),
tag_rollup as (
  select
    q.QuestionId,
    sum(ta.QuestionsWithTag) as TagPopularitySum,
    avg(cast(ta.QuestionsWithTag as numeric)) as TagPopularityAvg
  from question_tags qt
  join tag_activity ta on ta.tag = qt.tag
  join q_posts q on q.QuestionId = qt.QuestionId
  group by q.QuestionId
),
question_bins as (
  select
    tb.month_bucket,
    count(distinct tb.QuestionId) as QuestionsInMonth
  from time_bins tb
  group by tb.month_bucket
),
final_scores as (
  select
    qm.QuestionId,
    qm.Title,
    qm.Tags,
    qm.QuestionScore,
    qm.ViewCount,
    qm.QuestionCreation,
    qm.QuestionOwnerId,
    qm.QuestionOwnerName,
    qm.QuestionOwnerRep,
    coalesce(am.HasAcceptedAnswer,0) as HasAcceptedAnswer,
    am.AcceptedAnswerScore,
    am.TopAnswerScore,
    coalesce(qb.QuestionsInMonth,0) as MonthQCount,
    coalesce(tr.TagPopularitySum,0) as TagPopularitySum,
    coalesce(tr.TagPopularityAvg,0) as TagPopularityAvg,
    coalesce(va2.UpVotes,0) + coalesce(va2.DownVotes,0) as TotalVotes,
    coalesce(qm.Favorites,0) as Favorites,
    coalesce(qm.BountyTotal,0) as BountyTotal,
    coalesce(qm.CommentCount,0) as CommentCount,
    coalesce(qm.LinkedCount,0) as LinkedCount,
    coalesce(qm.DuplicateCount,0) as DuplicateCount,
    coalesce(qm.TotalLinks,0) as TotalLinks,
    coalesce(case when qm.WasClosed = 1 then 1 else 0 end,0) as WasClosed,
    coalesce(case when qm.WasDeleted = 1 then 1 else 0 end,0) as WasDeleted,
    obm.OwnerTotalBadges,
    obm.OwnerTagBadges,
    abm.TopAnsGold,
    abm.TopAnsSilver,
    abm.TopAnsBronze,
    date_trunc('month', qm.QuestionCreation) as MonthBucket,
    row_number() over (order by qm.ViewCount desc NULLS LAST, qm.QuestionScore desc NULLS LAST) as RN_GlobalByViews,
    percent_rank() over (order by qm.QuestionScore) as PR_ByScore,
    ntile(10) over (order by coalesce(qm.ViewCount,0) desc) as Decile_ByViews
  from q_metrics qm
  left join acceptance_metrics am on am.QuestionId = qm.QuestionId
  left join votes_agg va2 on va2.PostId = qm.QuestionId
  left join time_bins tb on tb.QuestionId = qm.QuestionId
  left join question_bins qb on qb.month_bucket = tb.month_bucket
  left join tag_rollup tr on tr.QuestionId = qm.QuestionId
  left join owner_badge_mix obm on obm.QuestionId = qm.QuestionId
  left join answerer_badge_mix abm on abm.QuestionId = qm.QuestionId
),
dup_clusters as (
  select
    p.Id as RootId,
    array_remove(array_agg(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end), null) as DupsOfRoot,
    array_remove(array_agg(distinct case when pl2.LinkTypeId = 3 then pl2.PostId end), null) as RootsOfThis
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
  left join PostLinks pl2 on pl2.RelatedPostId = p.Id and pl2.LinkTypeId = 3
  group by p.Id
),
null_logic_probe as (
  select
    fs.QuestionId,
    case
      when coalesce(fs.CommentCount,0) = 0 and (fs.LinkedCount is null or fs.LinkedCount = 0) then 'QUIET'
      when fs.CommentCount is null and fs.LinkedCount is not null then 'COMMENT_NULL_LINKED'
      when fs.CommentCount is not null and fs.LinkedCount is null then 'LINK_NULL_COMMENT'
      else 'ACTIVE'
    end as InteractionClass,
    case
      when fs.HasAcceptedAnswer = 1 and (fs.DuplicateCount is null or fs.DuplicateCount = 0) then 1
      when fs.HasAcceptedAnswer = 0 and coalesce(fs.DuplicateCount,0) > 0 then -1
      else 0
    end as QualitySignal
  from final_scores fs
),
correlated_probe as (
  select
    fs.QuestionId,
    exists (
      select 1
      from Posts a
      where a.ParentId = fs.QuestionId
        and a.PostTypeId = 2
        and a.Score > fs.QuestionScore
    ) as HasAnswerOutscoringQuestion
  from final_scores fs
)
select
  fs.QuestionId,
  coalesce(fs.Title, '[no title]') as Title,
  fs.QuestionOwnerName,
  fs.QuestionOwnerRep,
  fs.QuestionScore,
  fs.ViewCount,
  fs.TotalVotes,
  fs.Favorites,
  fs.BountyTotal,
  fs.HasAcceptedAnswer,
  fs.AcceptedAnswerScore,
  fs.TopAnswerScore,
  fs.MonthBucket,
  fs.MonthQCount,
  fs.TagPopularitySum,
  fs.TagPopularityAvg,
  fs.CommentCount,
  fs.LinkedCount,
  fs.DuplicateCount,
  fs.TotalLinks,
  fs.WasClosed,
  fs.WasDeleted,
  fs.OwnerTotalBadges,
  fs.OwnerTagBadges,
  fs.TopAnsGold,
  fs.TopAnsSilver,
  fs.TopAnsBronze,
  fs.RN_GlobalByViews,
  fs.PR_ByScore,
  fs.Decile_ByViews,
  nl.InteractionClass,
  nl.QualitySignal,
  cp.HasAnswerOutscoringQuestion,
  array_length(dc.DupsOfRoot, 1) as NumDupsOutgoing,
  array_length(dc.RootsOfThis, 1) as NumDupsIncoming,
  greatest(
    coalesce(fs.ViewCount, 0) / nullif(1 + abs(fs.QuestionScore), 0) 
      + coalesce(fs.TotalVotes,0)
      + 2 * coalesce(fs.Favorites,0)
      + 0.5 * coalesce(fs.CommentCount,0)
      + 3 * coalesce(fs.HasAcceptedAnswer,0)
      + 0.1 * coalesce(fs.TagPopularityAvg,0),
    0
  ) as CompositePerfScore,
  case
    when fs.Decile_ByViews <= 2 and fs.PR_ByScore <= 0.2 then 'LOW'
    when fs.Decile_ByViews >= 9 and fs.PR_ByScore >= 0.8 then 'HIGH'
    else 'MID'
  end as PerfTier
from final_scores fs
left join null_logic_probe nl on nl.QuestionId = fs.QuestionId
left join correlated_probe cp on cp.QuestionId = fs.QuestionId
left join dup_clusters dc on dc.RootId = fs.QuestionId
where
  (fs.ViewCount is null or fs.ViewCount > 0)
  and (fs.QuestionOwnerRep is null or fs.QuestionOwnerRep >= 1)
  and (
    fs.HasAcceptedAnswer = 1
    or coalesce(fs.DuplicateCount,0) > 0
    or fs.BountyTotal > 0
    or fs.WasClosed = 1
  )
order by CompositePerfScore desc NULLS LAST, fs.ViewCount desc NULLS LAST, fs.QuestionId
limit 500;