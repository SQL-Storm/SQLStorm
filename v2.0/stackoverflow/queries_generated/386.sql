-- {"query": "386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2980} 
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate as QuestionCreation,
    p.Score as QuestionScore,
    p.ViewCount,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select
    pa.Id as AnswerId,
    pa.ParentId as QuestionId,
    pa.OwnerUserId as AnswerOwnerId,
    pa.CreationDate as AnswerCreation,
    pa.Score as AnswerScore
  from Posts pa
  where pa.PostTypeId = 2
),
answers_ranked as (
  select
    a.*,
    row_number() over (partition by a.QuestionId order by a.Score desc nulls last, a.CreationDate asc) as rn_best,
    row_number() over (partition by a.QuestionId order by a.CreationDate asc) as rn_first,
    dense_rank() over (partition by a.QuestionId order by a.Score desc nulls last) as dr_score
  from a
),
best_answer as (
  select ar.*
  from answers_ranked ar
  where ar.rn_best = 1
),
first_answer as (
  select ar.*
  from answers_ranked ar
  where ar.rn_first = 1
),
users_agg as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreation,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    coalesce(nullif(trim(u.WebsiteUrl), ''), 'n/a') as WebsiteUrlNorm
  from Users u
),
badges_agg as (
  select
    b.UserId,
    count(*) as TotalBadges,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
votes_q as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as Upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as Downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    min(c.CreationDate) as FirstCommentDate,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
close_events as (
  select
    ph.PostId,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosed,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopened,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenCount,
    max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId
  from PostHistory ph
  group by ph.PostId
),
dupe_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as RelatedLinks
  from PostLinks pl
  group by pl.PostId
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(coalesce(q.Tags,'{}'), 2, greatest(length(coalesce(q.Tags,'{}'))-2,0)), '><')) as tag
  from q
),
tag_quality as (
  select
    te.QuestionId,
    avg(t.Count) as AvgTagCount,
    min(t.Count) as MinTagCount,
    max(t.Count) as MaxTagCount,
    count(*) as TagCount
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.tag)
  group by te.QuestionId
),
accepted_flags as (
  select
    q.QuestionId,
    case when q.AnswerCount > 0 and exists (
      select 1
      from Posts pa
      where pa.Id = (select AcceptedAnswerId from Posts p2 where p2.Id = q.QuestionId)
    ) then 1 else 0 end as HasAcceptedAnswer
  from q
),
first_activity as (
  select
    q.QuestionId,
    q.QuestionCreation,
    fa.AnswerCreation as FirstAnswerTime,
    extract(epoch from (fa.AnswerCreation - q.QuestionCreation)) as SecondsToFirstAnswer
  from q
  left join first_answer fa on fa.QuestionId = q.QuestionId
),
best_activity as (
  select
    q.QuestionId,
    ba.AnswerScore as BestAnswerScore,
    extract(epoch from (ba.AnswerCreation - q.QuestionCreation)) as SecondsToBestAnswer
  from q
  left join best_answer ba on ba.QuestionId = q.QuestionId
),
owner_stats as (
  select
    q.QuestionId,
    u.UserId as OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerRep,
    coalesce(b.TotalBadges,0) as OwnerBadges,
    coalesce(b.GoldBadges,0) as OwnerGold,
    coalesce(b.SilverBadges,0) as OwnerSilver,
    coalesce(b.BronzeBadges,0) as OwnerBronze
  from q
  left join users_agg u on u.UserId = q.OwnerUserId
  left join badges_agg b on b.UserId = u.UserId
),
string_derived as (
  select
    q.QuestionId,
    lower(coalesce(q.Title, '')) as title_lower,
    length(coalesce(q.Title,'')) as title_len,
    position('how' in lower(coalesce(q.Title,''))) > 0 as has_word_how,
    case when coalesce(q.Title,'') ~ '^\[.*\]' then substring(q.Title from 2 for position(']' in q.Title)-2) else null end as bracket_prefix
  from q
),
weights as (
  select
    q.QuestionId,
    -- scoring formula with mixed signals and null handling
    coalesce(q.QuestionScore,0) * 1.0
      + coalesce(vq.Upvotes,0) * 0.8
      - coalesce(vq.Downvotes,0) * 1.2
      + least(coalesce(vq.Favorites,0), 100) * 0.5
      + least(coalesce(vq.BountyAmountTotal,0), 500) * 0.02
      + coalesce(ta.AvgTagCount,0) * 0.001
      + case when af.HasAcceptedAnswer = 1 then 2.0 else 0.0 end
      - case when ce.CloseCount > 0 then 5.0 else 0.0 end
      + case when sd.has_word_how then 0.3 else 0.0 end
      + case when sd.title_len between 0 and 20 then -0.5 when sd.title_len between 21 and 60 then 0.2 else 0.0 end
      + coalesce(ds.DuplicateLinks,0) * -0.7
      + coalesce(ds.RelatedLinks,0) * 0.1
      + case when oq.OwnerRep >= 10000 then 0.8 when oq.OwnerRep >= 1000 then 0.3 else 0.0 end
      + case when fa.SecondsToFirstAnswer is null then -1.0 else greatest(0.0, 1.5 - (fa.SecondsToFirstAnswer/86400.0)) end
      + case when ba.SecondsToBestAnswer is null then 0.0 else greatest(0.0, 1.0 - (ba.SecondsToBestAnswer/86400.0)) end
    as PerfScore
  from q
  left join votes_q vq on vq.PostId = q.QuestionId
  left join tag_quality ta on ta.QuestionId = q.QuestionId
  left join accepted_flags af on af.QuestionId = q.QuestionId
  left join close_events ce on ce.PostId = q.QuestionId
  left join dupe_links ds on ds.PostId = q.QuestionId
  left join owner_stats oq on oq.QuestionId = q.QuestionId
  left join string_derived sd on sd.QuestionId = q.QuestionId
  left join first_activity fa on fa.QuestionId = q.QuestionId
  left join best_activity ba on ba.QuestionId = q.QuestionId
),
recent_active as (
  select
    q.QuestionId,
    p.LastActivityDate,
    row_number() over (order by p.LastActivityDate desc nulls last) as rn_activity
  from q
  join Posts p on p.Id = q.QuestionId
  where p.LastActivityDate is not null
),
normalized as (
  select
    w.QuestionId,
    w.PerfScore,
    rank() over (order by w.PerfScore desc nulls last) as r_perf,
    percent_rank() over (order by w.PerfScore) as pr_perf
  from weights w
),
quality_flags as (
  select
    n.QuestionId,
    case
      when n.PerfScore is null then 'unknown'
      when n.PerfScore >= (select percentile_cont(0.9) within group (order by PerfScore) from normalized) then 'top10'
      when n.PerfScore <= (select percentile_cont(0.1) within group (order by PerfScore) from normalized) then 'bottom10'
      else 'middle'
    end as PerfBucket
  from normalized n
),
posttype_checks as (
  select
    p.Id as QuestionId,
    case when pt.Name ilike '%question%' then 1 else 0 end as IsQuestionType
  from Posts p
  left join PostTypes pt on pt.Id = p.PostTypeId
  where p.PostTypeId = 1
)
select
  q.QuestionId,
  coalesce(q.Title, '(no title)') as Title,
  q.QuestionCreation,
  q.ViewCount,
  q.QuestionScore,
  coalesce(ta.TagCount,0) as TagCount,
  coalesce(ta.AvgTagCount,0) as AvgTagPopularity,
  coalesce(vq.Upvotes,0) as Upvotes,
  coalesce(vq.Downvotes,0) as Downvotes,
  coalesce(vq.Favorites,0) as Favorites,
  coalesce(vq.BountyAmountTotal,0) as BountyAmount,
  coalesce(ca.CommentCount,0) as CommentCount,
  ca.MaxCommentScore,
  ce.FirstClosed,
  ce.LastReopened,
  ce.CloseCount,
  ce.ReopenCount,
  ce.LastCloseReasonId,
  ds.DuplicateLinks,
  ds.RelatedLinks,
  af.HasAcceptedAnswer,
  fa.FirstAnswerTime,
  ba.SecondsToBestAnswer,
  oa.OwnerName,
  oa.OwnerRep,
  oa.OwnerBadges,
  sd.title_lower,
  sd.bracket_prefix,
  n.PerfScore,
  n.r_perf,
  n.pr_perf,
  qf.PerfBucket,
  ra.LastActivityDate,
  ptc.IsQuestionType
from q
left join votes_q vq on vq.PostId = q.QuestionId
left join comments_agg ca on ca.PostId = q.QuestionId
left join close_events ce on ce.PostId = q.QuestionId
left join dupe_links ds on ds.PostId = q.QuestionId
left join tag_quality ta on ta.QuestionId = q.QuestionId
left join accepted_flags af on af.QuestionId = q.QuestionId
left join first_activity fa on fa.QuestionId = q.QuestionId
left join best_activity ba on ba.QuestionId = q.QuestionId
left join owner_stats oa on oa.QuestionId = q.QuestionId
left join string_derived sd on sd.QuestionId = q.QuestionId
left join normalized n on n.QuestionId = q.QuestionId
left join quality_flags qf on qf.QuestionId = q.QuestionId
left join recent_active ra on ra.QuestionId = q.QuestionId
left join posttype_checks ptc on ptc.QuestionId = q.QuestionId
where
  (q.QuestionCreation >= now() - interval '5 years' or q.ViewCount > 1000)
  and coalesce(q.Title,'') is not null
  and (
    ds.DuplicateLinks is null
    or ds.DuplicateLinks = 0
    or q.ViewCount > 5000
  )
  and (
    ce.CloseCount is null
    or ce.ReopenCount >= coalesce(ce.CloseCount,0) - 1
  )
  and (
    sd.bracket_prefix is null
    or length(sd.bracket_prefix) between 1 and 25
  )
order by
  n.r_perf nulls last,
  coalesce(ra.LastActivityDate, q.QuestionCreation) desc,
  q.QuestionId
limit 500;