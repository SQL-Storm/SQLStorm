-- {"query": "955.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4137}
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
    p.ClosedDate,
    p.LastActivityDate
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreation
  from Posts a
  where a.PostTypeId = 2
),
user_dims as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate as UserCreated,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormalizedLocation,
    coalesce(nullif(trim(u.DisplayName), ''), '(anonymous)') as DisplayName,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews
  from Users u
),
answerers as (
  select
    a.QuestionId,
    a.AnswerId,
    a.AnswerOwnerId,
    a.AnswerScore,
    a.AnswerCreation,
    ud.Reputation as AnswererRep,
    ud.NormalizedLocation as AnswererLocation
  from a_posts a
  left join user_dims ud on ud.UserId = a.AnswerOwnerId
),
accepted_answer as (
  select
    q.QuestionId,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerOwnerId as AcceptedOwnerId,
    aa.AnswerScore as AcceptedScore,
    aa.AnswerCreation as AcceptedCreation
  from q_posts q
  left join a_posts aa on aa.AnswerId = q.AcceptedAnswerId
),
questioner as (
  select
    q.QuestionId,
    ud.UserId as QuestionOwnerId,
    ud.Reputation as QuestionerRep,
    ud.DisplayName as QuestionerName,
    ud.NormalizedLocation as QuestionerLocation
  from q_posts q
  left join user_dims ud on ud.UserId = q.QuestionOwnerId
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
    sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
    min(case when v.VoteTypeId = 2 then v.CreationDate else null end) as FirstUpvoteAt,
    max(case when v.VoteTypeId = 2 then v.CreationDate else null end) as LastUpvoteAt
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    avg(c.Score) as AvgCommentScore,
    min(c.CreationDate) as FirstCommentAt,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
links_agg as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount,
    count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DistinctDups
  from PostLinks pl
  group by pl.PostId
),
closures as (
  select
    ph.PostId,
    min(ph.CreationDate) as FirstClosedAt,
    max(ph.CreationDate) as LastClosedAt,
    count(*) as CloseEvents,
    string_agg(distinct crt.Name, ', ' order by crt.Name) as CloseReasons
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes crt
    on cast(crt.Id as varchar) = nullif(ph.Comment,'')
  group by ph.PostId
),
tag_expand as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q_posts q
  where q.Tags is not null and length(q.Tags) >= 2
),
tag_rank as (
  select
    QuestionId,
    tag,
    row_number() over (partition by QuestionId order by tag) as tag_pos,
    count(*) over (partition by QuestionId) as tag_cnt
  from tag_expand
),
top_tags as (
  select
    tr.QuestionId,
    string_agg(tr.tag, '|' order by tr.tag_pos) as TagsPipe,
    max(case when tr.tag_pos = 1 then tr.tag end) as FirstTag,
    max(case when tr.tag_pos = tr.tag_cnt then tr.tag end) as LastTag
  from tag_rank tr
  group by tr.QuestionId
),
answer_stats as (
  select
    a.QuestionId,
    count(*) as AnswerCount,
    count(*) filter (where a.AnswerScore > 0) as PositiveAnswers,
    sum(coalesce(a.AnswerScore,0)) as TotalAnswerScore,
    max(a.AnswerScore) as MaxAnswerScore,
    min(a.AnswerScore) as MinAnswerScore,
    percentile_cont(0.5) within group (order by a.AnswerScore) as MedianAnswerScore,
    min(a.AnswerCreation) as FirstAnswerAt,
    max(a.AnswerCreation) as LastAnswerAt
  from answerers a
  group by a.QuestionId
),
first_response as (
  select
    a.QuestionId,
    a.AnswerId as FirstAnswerId,
    a.AnswerOwnerId as FirstAnswerOwnerId,
    a.AnswerCreation as FirstAnswerAt,
    a.AnswerScore as FirstAnswerScore,
    row_number() over (partition by a.QuestionId order by a.AnswerCreation) as rn
  from answerers a
),
first_response_only as (
  select * from first_response where rn = 1
),
hotness as (
  select
    q.QuestionId,
    q.QuestionCreation,
    q.ViewCount,
    coalesce(va.UpVotes,0) as QUp,
    coalesce(va.DownVotes,0) as QDown,
    coalesce(ca.CommentCount,0) as QComments,
    coalesce(ls.LinkedCount,0) as QLinked,
    coalesce(ls.DuplicateCount,0) as QDup,
    coalesce(ans.AnswerCount,0) as Answers,
    coalesce(ans.TotalAnswerScore,0) as AnswerScoreSum,
    extract(epoch from (timestamp '2024-10-01 12:34:56' - q.QuestionCreation))/3600.0 as HoursSinceAsk
  from q_posts q
  left join votes_agg va on va.PostId = q.QuestionId
  left join comments_agg ca on ca.PostId = q.QuestionId
  left join links_agg ls on ls.PostId = q.QuestionId
  left join answer_stats ans on ans.QuestionId = q.QuestionId
),
hotness_calc as (
  select
    h.QuestionId,
    h.QuestionCreation,
    h.ViewCount,
    h.QUp,
    h.QDown,
    h.QComments,
    h.QLinked,
    h.QDup,
    h.Answers,
    h.AnswerScoreSum,
    h.HoursSinceAsk,
    (
      (ln(1 + greatest(h.ViewCount,0)) * 0.3) +
      (ln(1 + greatest(h.QUp,0)) * 0.6) -
      (ln(1 + greatest(h.QDown,0)) * 0.5) +
      (sqrt(greatest(h.QComments,0)) * 0.4) +
      (sqrt(greatest(h.Answers,0)) * 0.7) +
      (ln(1 + greatest(h.AnswerScoreSum,0)) * 0.8) +
      (case when h.QDup > 0 then -1.5 else 0 end) +
      (case when h.QLinked > 4 then 0.5 else 0 end)
    ) / nullif(1 + ln(1 + h.HoursSinceAsk), 0) as HotnessScore
  from hotness h
),
dupe_clusters as (
  select
    q.QuestionId,
    case when la.DistinctDups is not null and la.DistinctDups > 0 then 1 else 0 end as IsDuplicate,
    coalesce(la.DistinctDups, 0) as DuplicateTargets
  from q_posts q
  left join links_agg la on la.PostId = q.QuestionId
),
post_age as (
  select
    q.QuestionId,
    q.QuestionCreation,
    extract(epoch from (timestamp '2024-10-01 12:34:56' - q.QuestionCreation)) / 86400.0 as AgeDays
  from q_posts q
),
post_flags as (
  select
    q.QuestionId,
    case when q.ClosedDate is not null then 1 else 0 end as IsClosed,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
    case when q.LastActivityDate is not null and q.LastActivityDate > (timestamp '2024-10-01 12:34:56' - interval '30 days') then 1 else 0 end as ActiveRecently
  from q_posts q
),
question_quality as (
  select
    q.QuestionId,
    q.QuestionScore,
    coalesce(va.UpVotes,0) as UpVotes,
    coalesce(va.DownVotes,0) as DownVotes,
    coalesce(ca.CommentCount,0) as Comments,
    coalesce(va.Favorites,0) as Favorites,
    case
      when q.QuestionScore is null then null
      when q.QuestionScore >= 10 then 'Great'
      when q.QuestionScore >= 3 then 'Good'
      when q.QuestionScore >= 0 then 'Average'
      else 'Poor'
    end as ScoreBucket,
    case
      when coalesce(va.DownVotes,0) = 0 then null
      else round(cast(coalesce(va.UpVotes,0) as numeric) / nullif(cast(coalesce(va.DownVotes,0) as numeric),0), 2)
    end as UpDownRatio
  from q_posts q
  left join votes_agg va on va.PostId = q.QuestionId
  left join comments_agg ca on ca.PostId = q.QuestionId
),
post_edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditAt,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditAt,
    count(*) filter (where ph.PostHistoryTypeId in (24)) as SuggestedEditsApplied,
    count(*) filter (where ph.PostHistoryTypeId in (50)) as CommunityBumps
  from PostHistory ph
  group by ph.PostId
),
rep_bands as (
  select
    ud.UserId,
    case
      when ud.Reputation >= 100000 then 'Legend'
      when ud.Reputation >= 25000 then 'Elite'
      when ud.Reputation >= 10000 then 'Veteran'
      when ud.Reputation >= 3000 then 'Seasoned'
      when ud.Reputation >= 1000 then 'Established'
      when ud.Reputation >= 100 then 'Contributor'
      else 'Newbie'
    end as RepBand
  from user_dims ud
),
badge_summary as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as Gold,
    sum(case when b.Class = 2 then 1 else 0 end) as Silver,
    sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
    sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
    count(*) as TotalBadges,
    min(b.Date) as FirstBadgeAt,
    max(b.Date) as LastBadgeAt
  from Badges b
  group by b.UserId
),
answerer_diversity as (
  select
    a.QuestionId,
    count(distinct a.AnswerOwnerId) as DistinctAnswerers,
    count(distinct a.AnswererLocation) filter (where a.AnswererLocation is not null) as DistinctLocations
  from answerers a
  group by a.QuestionId
),
question_title_features as (
  select
    q.QuestionId,
    length(coalesce(q.Title, '')) as TitleLen,
    length(regexp_replace(coalesce(q.Title,''), '[^A-Za-z0-9 ]', '', 'g')) as AlnumTitleLen,
    (length(coalesce(q.Title,'')) - length(replace(coalesce(q.Title,''), '?', ''))) as QMarks,
    (length(coalesce(q.Title,'')) - length(replace(coalesce(q.Title,''), '!', ''))) as Exclaims,
    case when lower(coalesce(q.Title,'')) like '%how%' or lower(coalesce(q.Title,'')) like '%why%' or lower(coalesce(q.Title,'')) like '%what%' or lower(coalesce(q.Title,'')) like '%where%' or lower(coalesce(q.Title,'')) like '%when%' or lower(coalesce(q.Title,'')) like '%can%' or lower(coalesce(q.Title,'')) like '%should%' then 1 else 0 end as HasInterrogative
  from q_posts q
),
stringified as (
  select
    q.QuestionId,
    ('Q' || cast(q.QuestionId as varchar)) as QuestionKey,
    coalesce(q.Title, '(no title)') || ' [' || coalesce(tt.FirstTag, 'untagged') || ']' as PrettyTitle,
    '[' || coalesce(tt.TagsPipe, '') || ']' as TagList
  from q_posts q
  left join top_tags tt on tt.QuestionId = q.QuestionId
),
rankings as (
  select
    q.QuestionId,
    dense_rank() over (order by hc.HotnessScore desc nulls last) as HotRank,
    row_number() over (order by coalesce(va.UpVotes,0) desc, coalesce(va.DownVotes,0)) as VoteRank,
    row_number() over (order by q.ViewCount desc nulls last) as ViewRank,
    ntile(10) over (order by coalesce(q.ViewCount,0)) as ViewDecile
  from q_posts q
  left join votes_agg va on va.PostId = q.QuestionId
  left join hotness_calc hc on hc.QuestionId = q.QuestionId
),
accepted_latency as (
  select
    q.QuestionId,
    case
      when q.AcceptedAnswerId is null then null
      else extract(epoch from (aa.AcceptedCreation - q.QuestionCreation)) / 3600.0
    end as HoursToAccept
  from q_posts q
  left join accepted_answer aa on aa.QuestionId = q.QuestionId
)
select
  s.QuestionKey,
  s.PrettyTitle,
  q.Title,
  q.Tags,
  tt.FirstTag,
  tt.LastTag,
  qa.QuestionerName,
  qa.QuestionerLocation,
  rbq.RepBand as QuestionerBand,
  coalesce(bs_q.TotalBadges,0) as QuestionerBadges,
  q.QuestionCreation,
  pa.AgeDays,
  q.ViewCount,
  qa.QuestionerRep,
  qq.QuestionScore,
  qq.UpVotes as QUpVotes,
  qq.DownVotes as QDownVotes,
  qq.UpDownRatio,
  qq.Favorites as QFavorites,
  ca.CommentCount as QComments,
  la.LinkedCount,
  la.DuplicateCount,
  dc.IsDuplicate,
  dc.DuplicateTargets,
  coalesce(pe.EditCount,0) as EditCount,
  pe.FirstEditAt,
  pe.LastEditAt,
  coalesce(pe.SuggestedEditsApplied,0) as SuggestedEdits,
  coalesce(pe.CommunityBumps,0) as CommunityBumps,
  coalesce(cl.CloseEvents,0) as CloseEvents,
  cl.FirstClosedAt,
  cl.LastClosedAt,
  cl.CloseReasons,
  pf.IsClosed,
  pf.HasAcceptedAnswer,
  pf.ActiveRecently,
  ans.AnswerCount,
  ans.PositiveAnswers,
  ans.TotalAnswerScore,
  ans.MaxAnswerScore,
  ans.MinAnswerScore,
  ans.MedianAnswerScore,
  ans.FirstAnswerAt,
  ans.LastAnswerAt,
  fr.FirstAnswerId,
  fr.FirstAnswerOwnerId,
  fr.FirstAnswerAt,
  fr.FirstAnswerScore,
  al.HoursToAccept,
  ac.AcceptedAnswerId,
  ac.AcceptedOwnerId,
  ac.AcceptedScore,
  ac.AcceptedCreation,
  ad.DistinctAnswerers,
  ad.DistinctLocations,
  tf.TitleLen,
  tf.AlnumTitleLen,
  tf.QMarks,
  tf.Exclaims,
  tf.HasInterrogative,
  hc.HotnessScore,
  r.HotRank,
  r.VoteRank,
  r.ViewRank,
  r.ViewDecile,
  sg.TagList
from q_posts q
left join questioner qa on qa.QuestionId = q.QuestionId
left join rep_bands rbq on rbq.UserId = qa.QuestionOwnerId
left join badge_summary bs_q on bs_q.UserId = qa.QuestionOwnerId
left join post_age pa on pa.QuestionId = q.QuestionId
left join question_quality qq on qq.QuestionId = q.QuestionId
left join comments_agg ca on ca.PostId = q.QuestionId
left join links_agg la on la.PostId = q.QuestionId
left join dupe_clusters dc on dc.QuestionId = q.QuestionId
left join post_edits pe on pe.PostId = q.QuestionId
left join closures cl on cl.PostId = q.QuestionId
left join post_flags pf on pf.QuestionId = q.QuestionId
left join answer_stats ans on ans.QuestionId = q.QuestionId
left join first_response_only fr on fr.QuestionId = q.QuestionId
left join accepted_answer ac on ac.QuestionId = q.QuestionId
left join accepted_latency al on al.QuestionId = q.QuestionId
left join answerer_diversity ad on ad.QuestionId = q.QuestionId
left join question_title_features tf on tf.QuestionId = q.QuestionId
left join hotness_calc hc on hc.QuestionId = q.QuestionId
left join rankings r on r.QuestionId = q.QuestionId
left join top_tags tt on tt.QuestionId = q.QuestionId
left join stringified s on s.QuestionId = q.QuestionId
left join stringified sg on sg.QuestionId = q.QuestionId
where
  coalesce(q.ViewCount,0) > 0
  and (qq.ScoreBucket IS DISTINCT FROM 'Poor' OR pf.HasAcceptedAnswer = 1)
  and (dc.IsDuplicate = 0 OR pf.IsClosed = 0)
order by
  hc.HotnessScore desc nulls last,
  qq.UpVotes desc nulls last,
  q.ViewCount desc nulls last
limit 500;