-- {"query": "587.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3128} 
with
q as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreation,
    p.Score as QuestionScore,
    p.ViewCount,
    p.OwnerUserId as AskerId,
    p.AcceptedAnswerId,
    p.Title,
    p.Tags,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName) as AskerDisplayName,
    u.Reputation as AskerReputation
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
a as (
  select
    pa.Id as AnswerId,
    pa.ParentId as QuestionId,
    pa.OwnerUserId as AnswererId,
    pa.Score as AnswerScore,
    pa.CreationDate as AnswerCreation
  from Posts pa
  where pa.PostTypeId = 2
),
qa as (
  select
    q.*,
    a.AnswerId,
    a.AnswererId,
    a.AnswerScore,
    a.AnswerCreation,
    case when q.AcceptedAnswerId = a.AnswerId then 1 else 0 end as IsAccepted
  from q
  left join a on a.QuestionId = q.QuestionId
),
answer_stats as (
  select
    QuestionId,
    count(*) filter (where AnswerId is not null) as AnswerCount,
    max(AnswerScore) as MaxAnswerScore,
    avg(AnswerScore) as AvgAnswerScore,
    sum(case when IsAccepted = 1 then 1 else 0 end) as AcceptedCount,
    min(AnswerCreation) as FirstAnswerAt
  from qa
  group by QuestionId
),
edits as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditEvents,
    count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseVotesEvents,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditAt
  from PostHistory ph
  join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
  group by ph.PostId
),
votes_agg as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId in (8,9)) as BountyEvents,
    sum(coalesce(v.BountyAmount,0)) as BountyTotal
  from Votes v
  group by v.PostId
),
tag_split as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
  where q.Tags is not null and q.Tags like '<%>'
),
tag_norm as (
  select
    QuestionId,
    lower(trim(tag)) as tag
  from tag_split
  where tag is not null and trim(tag) <> ''
),
hot_tags as (
  select
    t.TagName,
    t.Count as TagCount
  from Tags t
  where coalesce(t.IsModeratorOnly, 0) = 0
),
q_tag_rank as (
  select
    tn.QuestionId,
    tn.tag,
    ht.TagCount,
    row_number() over (partition by tn.QuestionId order by coalesce(ht.TagCount,0) desc, tn.tag) as tag_rank
  from tag_norm tn
  left join hot_tags ht on ht.TagName = tn.tag
),
best_tag as (
  select
    QuestionId,
    tag as DominantTag,
    TagCount as DominantTagCount
  from q_tag_rank
  where tag_rank = 1
),
linked as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks
  from PostLinks pl
  group by pl.PostId
),
dupe_of as (
  select
    pl.PostId as QuestionId,
    min(pl.RelatedPostId) as DupeTargetId
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId
),
comment_stats as (
  select
    c.PostId,
    count(*) as CommentCount,
    max(c.Score) as MaxCommentScore,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
asker_activity as (
  select
    u.Id as AskerId,
    sum(u.UpVotes) as LifetimeUpvotes,
    sum(u.DownVotes) as LifetimeDownvotes,
    sum(u.Views) as LifetimeProfileViews
  from Users u
  group by u.Id
),
age_bucket as (
  select
    q.QuestionId,
    case
      when q.QuestionCreation >= now() - interval '7 days' then '0-7d'
      when q.QuestionCreation >= now() - interval '30 days' then '8-30d'
      when q.QuestionCreation >= now() - interval '180 days' then '31-180d'
      when q.QuestionCreation >= now() - interval '365 days' then '181-365d'
      else '1y+'
    end as AgeBucket
  from q
),
accepted_latency as (
  select
    qa.QuestionId,
    min(extract(epoch from (qa.AnswerCreation - q.QuestionCreation))) filter (where qa.IsAccepted = 1) as AcceptedLatencySeconds
  from qa
  join q on q.QuestionId = qa.QuestionId
  group by qa.QuestionId
),
quality_score as (
  select
    q.QuestionId,
    (
      coalesce(v.UpVotes,0) * 3
      - coalesce(v.DownVotes,0) * 2
      + coalesce(a.AnswerCount,0) * 1
      + case when e.EditEvents > 0 then 2 else 0 end
      + least(coalesce(a.MaxAnswerScore,0), 50)
      + case when q.ViewCount is null then 0 else ln(1 + greatest(q.ViewCount,0)) end
      + case when al.AcceptedLatencySeconds is null then 0 else greatest(0, 100 - (al.AcceptedLatencySeconds/3600)::int) end
      + case when b.DominantTagCount >= 100000 then 10 when b.DominantTagCount >= 10000 then 5 else 0 end
      - coalesce(l.DuplicateLinks,0) * 5
    )::numeric as QualityScore
  from q
  left join votes_agg v on v.PostId = q.QuestionId
  left join answer_stats a on a.QuestionId = q.QuestionId
  left join edits e on e.QuestionId = q.QuestionId
  left join accepted_latency al on al.QuestionId = q.QuestionId
  left join best_tag b on b.QuestionId = q.QuestionId
  left join linked l on l.QuestionId = q.QuestionId
),
recent_badges as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldCount,
    count(*) filter (where b.Class = 2) as SilverCount,
    count(*) filter (where b.Class = 3) as BronzeCount,
    max(b.Date) as LastBadgeAt
  from Badges b
  where b.Date >= now() - interval '2 years'
  group by b.UserId
),
user_norm as (
  select
    u.Id as UserId,
    coalesce(nullif(trim(u.Location), ''), 'Unknown') as Location,
    coalesce(u.Reputation, 0) as Reputation,
    coalesce(u.UpVotes, 0) as UpVotes,
    coalesce(u.DownVotes, 0) as DownVotes,
    coalesce(u.Views, 0) as ProfileViews,
    date_part('year', age(now(), u.CreationDate))::int as AccountAgeYears
  from Users u
),
question_rank as (
  select
    q.QuestionId,
    dense_rank() over (order by qs.QualityScore desc nulls last, q.ViewCount desc nulls last, q.QuestionCreation desc) as QualityRank
  from q
  left join quality_score qs on qs.QuestionId = q.QuestionId
),
dupe_chain as (
  select
    d.QuestionId,
    d.DupeTargetId,
    case when d.DupeTargetId is not null and d.DupeTargetId = q.QuestionId then 1 else 0 end as SelfLoopFlag
  from dupe_of d
  left join q on q.QuestionId = d.DupeTargetId
),
final as (
  select
    q.QuestionId,
    q.Title,
    q.Tags,
    bt.DominantTag,
    coalesce(bt.DominantTagCount, 0) as DominantTagCount,
    q.QuestionCreation,
    q.ViewCount,
    q.QuestionScore,
    coalesce(ans.AnswerCount, 0) as AnswerCount,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(v.UpVotes, 0) as UpVotes,
    coalesce(v.DownVotes, 0) as DownVotes,
    coalesce(v.BountyEvents, 0) as BountyEvents,
    coalesce(v.BountyTotal, 0) as BountyTotal,
    coalesce(e.EditEvents, 0) as EditEvents,
    e.LastEditAt,
    coalesce(c.CommentCount, 0) as CommentCount,
    c.MaxCommentScore,
    c.LastCommentAt,
    ab.AgeBucket,
    al.AcceptedLatencySeconds,
    qs.QualityScore,
    qr.QualityRank,
    q.AskerId,
    q.AskerDisplayName,
    q.AskerReputation,
    un.Location as AskerLocation,
    un.AccountAgeYears,
    rb.GoldCount as AskerGoldBadges2y,
    rb.SilverCount as AskerSilverBadges2y,
    rb.BronzeCount as AskerBronzeBadges2y,
    rb.LastBadgeAt,
    coalesce(l.LinkedCount, 0) as LinkedCount,
    coalesce(l.DuplicateLinks, 0) as DuplicateLinks,
    dc.SelfLoopFlag as DupeSelfLoopFlag,
    case
      when q.Tags ilike '%<sql>%' and coalesce(ans.AnswerCount,0) > 3 then 'SQL Hot'
      when q.QuestionScore >= 10 and coalesce(v.UpVotes,0) >= 15 then 'Well Received'
      when coalesce(v.DownVotes,0) >= 5 then 'Controversial'
      when al.AcceptedLatencySeconds is null then 'Unresolved'
      else 'Normal'
    end as Category,
    substring(coalesce(q.Title,''), 1, 120) as TitlePreview
  from q
  left join answer_stats ans on ans.QuestionId = q.QuestionId
  left join votes_agg v on v.PostId = q.QuestionId
  left join edits e on e.QuestionId = q.QuestionId
  left join comment_stats c on c.PostId = q.QuestionId
  left join age_bucket ab on ab.QuestionId = q.QuestionId
  left join accepted_latency al on al.QuestionId = q.QuestionId
  left join quality_score qs on qs.QuestionId = q.QuestionId
  left join question_rank qr on qr.QuestionId = q.QuestionId
  left join best_tag bt on bt.QuestionId = q.QuestionId
  left join linked l on l.QuestionId = q.QuestionId
  left join dupe_chain dc on dc.QuestionId = q.QuestionId
  left join user_norm un on un.UserId = q.AskerId
  left join recent_badges rb on rb.UserId = q.AskerId
),
topn as (
  select
    f.*,
    row_number() over (
      partition by coalesce(f.DominantTag, 'unknown')
      order by f.QualityScore desc nulls last, f.ViewCount desc nulls last, f.QuestionCreation desc
    ) as rn_by_tag
  from final f
  where
    (
      f.QualityScore is not null
      or (f.UpVotes - f.DownVotes) >= 5
      or (f.AnswerCount >= 2 and f.ViewCount >= 100)
    )
    and coalesce(f.DupeSelfLoopFlag,0) = 0
    and not (f.Category = 'Unresolved' and f.AnswerCount = 0 and f.ViewCount < 20)
)
select
  t.DominantTag,
  t.QuestionId,
  t.TitlePreview,
  t.Category,
  t.QualityScore,
  t.QualityRank,
  t.QuestionScore,
  t.UpVotes,
  t.DownVotes,
  t.AnswerCount,
  t.MaxAnswerScore,
  t.ViewCount,
  t.AgeBucket,
  t.AcceptedLatencySeconds,
  t.LinkedCount,
  t.DuplicateLinks,
  t.BountyEvents,
  t.BountyTotal,
  t.EditEvents,
  coalesce(t.AskerDisplayName, 'Anonymous') as AskerDisplayName,
  t.AskerReputation,
  t.AskerLocation
from topn t
where t.rn_by_tag <= 20
union all
select
  'all' as DominantTag,
  t.QuestionId,
  t.TitlePreview,
  t.Category,
  t.QualityScore,
  t.QualityRank,
  t.QuestionScore,
  t.UpVotes,
  t.DownVotes,
  t.AnswerCount,
  t.MaxAnswerScore,
  t.ViewCount,
  t.AgeBucket,
  t.AcceptedLatencySeconds,
  t.LinkedCount,
  t.DuplicateLinks,
  t.BountyEvents,
  t.BountyTotal,
  t.EditEvents,
  coalesce(t.AskerDisplayName, 'Anonymous') as AskerDisplayName,
  t.AskerReputation,
  t.AskerLocation
from (
  select t.*,
         row_number() over (order by t.QualityScore desc nulls last, t.ViewCount desc nulls last, t.QuestionCreation desc) as rn_overall
  from topn t
) t
where t.rn_overall <= 50
order by DominantTag, QualityScore desc nulls last, ViewCount desc nulls last, QuestionCreation desc;