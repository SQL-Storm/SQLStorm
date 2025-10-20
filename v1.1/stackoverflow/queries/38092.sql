with recent_q as (
  select p.Id as QuestionId,
         p.OwnerUserId as OwnerId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.AcceptedAnswerId,
         p.AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts)
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
q_stats as (
  select
    rq.QuestionId,
    rq.OwnerId,
    rq.CreationDate,
    rq.Score as QuestionScore,
    rq.ViewCount,
    rq.Tags,
    rq.AcceptedAnswerId,
    rq.AnswerCount,
    coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as NetVotes,
    count(distinct c.Id) as CommentCount,
    count(distinct pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36)) as MajorEvents
  from recent_q rq
  left join Votes v on v.PostId = rq.QuestionId and v.VoteTypeId in (2,3)
  left join Comments c on c.PostId = rq.QuestionId
  left join PostLinks pl on pl.PostId = rq.QuestionId
  left join PostHistory ph on ph.PostId = rq.QuestionId
  group by rq.QuestionId, rq.OwnerId, rq.CreationDate, rq.Score, rq.ViewCount, rq.Tags, rq.AcceptedAnswerId, rq.AnswerCount
),
a_stats as (
  select
    an.QuestionId,
    count(*) as TotalAnswers,
    cast(avg(an.AnswerScore) as numeric(18,4)) as AvgAnswerScore,
    max(an.AnswerScore) as MaxAnswerScore,
    min(an.AnswerScore) as MinAnswerScore,
    percentile_cont(0.5) within group (order by an.AnswerScore) as MedianAnswerScore,
    min(an.AnswerCreationDate) as FirstAnswerAt,
    max(an.AnswerCreationDate) as LastAnswerAt,
    count(*) filter (where an.AnswerScore >= 1) as UpvotedAnswers,
    count(*) filter (where an.AnswerScore < 0) as NegativeAnswers
  from answers an
  group by an.QuestionId
),
accepted as (
  select
    rq.QuestionId,
    a.AnswerId as AcceptedId,
    a.AnswerScore as AcceptedScore,
    extract(epoch from (a.AnswerCreationDate - rq.CreationDate))/3600.0 as HoursToAccept
  from recent_q rq
  join answers a on a.AnswerId = rq.AcceptedAnswerId
),
owner_profile as (
  select
    u.Id as OwnerId,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    cast(date_part('year', age(cast('2024-10-01' as date), u.CreationDate)) as integer) as AccountAgeYears,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(*) as TotalBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
tag_expansion as (
  select
    qs.QuestionId,
    unnest(string_to_array(substring(qs.Tags, 2, length(qs.Tags)-2), '><')) as TagName
  from q_stats qs
  where qs.Tags is not null and qs.Tags like '<%>'
),
tag_ranks as (
  select
    te.QuestionId,
    te.TagName,
    t.Count as TagGlobalCount,
    rank() over (partition by te.QuestionId order by t.Count desc nulls last) as TagPopularityRank
  from tag_expansion te
  left join Tags t on t.TagName = te.TagName
),
primary_tag as (
  select tr.QuestionId,
         tr.TagName as PrimaryTag,
         tr.TagGlobalCount as PrimaryTagGlobalCount
  from tag_ranks tr
  join (
    select QuestionId, min(TagPopularityRank) as rnk
    from tag_ranks
    group by QuestionId
  ) x on x.QuestionId = tr.QuestionId and tr.TagPopularityRank = x.rnk
),
hotness as (
  select
    qs.QuestionId,
    cast((coalesce(qs.NetVotes,0) * 3 + coalesce(qs.CommentCount,0) + coalesce(qs.DuplicateLinks,0)*-5 + coalesce(qs.MajorEvents,0)) as integer) as InteractionScore,
    case when qs.ViewCount > 0 then ln(cast(qs.ViewCount as numeric)) else 0 end
      + case when qs.QuestionScore is not null then qs.QuestionScore * 0.25 else 0 end
      + coalesce(a.TotalAnswers,0) * 0.5
      + coalesce(a.UpvotedAnswers,0) * 0.2
      as HotnessScore
  from q_stats qs
  left join a_stats a on a.QuestionId = qs.QuestionId
),
time_bins as (
  select
    qs.QuestionId,
    case
      when qs.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '7 days' then 'd07'
      when qs.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 'd30'
      when qs.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' then 'd90'
      else 'd180'
    end as RecencyBucket
  from q_stats qs
),
final as (
  select
    qs.QuestionId,
    qs.CreationDate,
    tp.PrimaryTag,
    tp.PrimaryTagGlobalCount,
    qs.ViewCount,
    qs.QuestionScore,
    qs.NetVotes,
    qs.CommentCount,
    qs.DuplicateLinks,
    qs.MajorEvents,
    coalesce(a.TotalAnswers,0) as TotalAnswers,
    a.AvgAnswerScore,
    a.MedianAnswerScore,
    a.FirstAnswerAt,
    a.LastAnswerAt,
    acc.AcceptedId,
    acc.AcceptedScore,
    acc.HoursToAccept,
    op.Reputation as OwnerReputation,
    op.AccountAgeYears as OwnerAgeYears,
    op.GoldBadges,
    op.SilverBadges,
    op.BronzeBadges,
    h.InteractionScore,
    h.HotnessScore,
    tb.RecencyBucket,
    row_number() over (
      partition by tb.RecencyBucket
      order by h.HotnessScore desc nulls last, qs.ViewCount desc nulls last, qs.QuestionId desc
    ) as BucketRank
  from q_stats qs
  left join a_stats a on a.QuestionId = qs.QuestionId
  left join accepted acc on acc.QuestionId = qs.QuestionId
  left join owner_profile op on op.OwnerId = qs.OwnerId
  left join hotness h on h.QuestionId = qs.QuestionId
  left join time_bins tb on tb.QuestionId = qs.QuestionId
  left join primary_tag tp on tp.QuestionId = qs.QuestionId
)
select *
from final
where BucketRank <= 100
order by RecencyBucket, BucketRank;