-- {"query": "2427.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1210}
with RecursiveUserPosts as (
  select u.Id as UserId, u.DisplayName, p.Id as PostId, p.PostTypeId, p.Score, p.CreationDate,
    row_number() over (partition by u.Id order by p.CreationDate desc) as rn
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  where u.Reputation > 1000
), LatestQuestions as (
  select rp.UserId, rp.PostId, rp.Score, rp.CreationDate, rp.DisplayName, p.Tags
  from RecursiveUserPosts rp
  join Posts p on p.Id = rp.PostId
  where rp.PostTypeId = 1
    and rp.rn <= 5
), AnswerStats as (
  select p.ParentId as QuestionId,
    count(*) as AnswerCount,
    avg(case when v.VoteTypeId = 2 then 1 else 0 end) as AvgUpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
  from Posts p
  left join Votes v on v.PostId = p.Id
  where p.PostTypeId = 2
  group by p.ParentId
), QuestionCloseInfo as (
  select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDate
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
  where ph.PostHistoryTypeId = 10
), UserBadgeCounts as (
  select b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId
), PostCommentsAggregates as (
  select c.PostId,
    count(*) as CommentCount,
    max(c.CreationDate) as LastCommentDate,
    string_agg(distinct coalesce(c.UserDisplayName,'[Anonymous]'), ', ') as CommenterNames
  from Comments c
  group by c.PostId
), PostBestAnswerVotes as (
  select p.Id as QuestionId, p.AcceptedAnswerId,
    coalesce(vup.UpVotes,0) as AcceptedAnswerUpVotes,
    coalesce(vup.DownVotes,0) as AcceptedAnswerDownVotes
  from Posts p
  left join (
    select a.Id,
      count(*) filter (where v.VoteTypeId=2) as UpVotes,
      count(*) filter (where v.VoteTypeId=3) as DownVotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId=2
    group by a.Id
  ) vup on vup.Id = p.AcceptedAnswerId
  where p.PostTypeId = 1
), TagPopularity as (
  select tag as Tag,
    count(*) as UsageCount
  from (
    select unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><')) as tag
    from Posts
    where Tags is not null and PostTypeId=1
  ) t
  group by tag
), UserActivityWindows as (
  select
    p.OwnerUserId,
    p.Id as PostId,
    p.PostTypeId,
    p.Score,
    p.CreationDate,
    sum(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 4 preceding and current row) as ScoreLast5Posts,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate) as PostSequence
  from Posts p
  where p.OwnerUserId is not null
)
select
  lq.DisplayName as UserName,
  lq.PostId as QuestionId,
  lq.Score as QuestionScore,
  coalesce(a.AnswerCount,0) as TotalAnswers,
  coalesce(a.AvgUpVotes,0) as AvgAnswerUpVotes,
  coalesce(a.TotalDownVotes,0) as TotalAnswerDownVotes,
  pbc.AcceptedAnswerUpVotes,
  pbc.AcceptedAnswerDownVotes,
  pci.CloseReason,
  pci.CloseDate,
  uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges,
  pca.CommentCount,
  pca.LastCommentDate,
  left(pca.CommenterNames, 50) || case when length(pca.CommenterNames) > 50 then '...' else '' end as CommentersSample,
  tp.Tag,
  tp.UsageCount,
  uaw.ScoreLast5Posts,
  case when uaw.ScoreLast5Posts > 100 then 'High Engagement' else 'Normal' end as EngagementLevel
from LatestQuestions lq
left join AnswerStats a on a.QuestionId = lq.PostId
left join PostBestAnswerVotes pbc on pbc.QuestionId = lq.PostId
left join QuestionCloseInfo pci on pci.PostId = lq.PostId
left join UserBadgeCounts uba on uba.UserId = lq.UserId
left join PostCommentsAggregates pca on pca.PostId = lq.PostId
left join TagPopularity tp on tp.Tag = (
    select (string_to_array(substring(lq.Tags from 2 for length(lq.Tags)-2), '><'))[1]
)
left join UserActivityWindows uaw on uaw.OwnerUserId = lq.UserId and uaw.PostId = lq.PostId
where lq.DisplayName is not null
  and (pci.CloseReason is null or pci.CloseDate > lq.CreationDate - interval '30 days')
order by uba.GoldBadges desc nulls last, lq.Score desc
limit 50;