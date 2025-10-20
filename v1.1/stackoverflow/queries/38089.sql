with recent_q as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         p.Title,
         row_number() over (order by p.CreationDate desc, p.Score desc, p.Id desc) as rn
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (
      select date_trunc('month', max(CreationDate)) - interval '6 months'
      from Posts
      where PostTypeId = 1
    )
),
top_recent_q as (
  select * from recent_q where rn <= 5000
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  join top_recent_q q on q.QuestionId = a.ParentId
  where a.PostTypeId = 2
),
first_answer as (
  select QuestionId,
         min(AnswerCreationDate) as FirstAnswerDate
  from answers
  group by QuestionId
),
votes_agg as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 12 then 1 else 0 end) as SpamVotes,
         sum(case when v.VoteTypeId = 10 then 1 else 0 end) as DeleteVotes
  from Votes v
  join top_recent_q q on q.QuestionId = v.PostId
  group by v.PostId
),
comments_agg as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentDate
  from Comments c
  join top_recent_q q on q.QuestionId = c.PostId
  group by c.PostId
),
links_agg as (
  select pl.PostId,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount
  from PostLinks pl
  join top_recent_q q on q.QuestionId = pl.PostId
  group by pl.PostId
),
tag_expanded as (
  -- Use standard SQL string functions: substring and length, and split by '><'.
  -- Build inner string without leading '<' and trailing '>'
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags FROM 2 FOR (length(q.Tags) - 2)), '><')) as tag
  from top_recent_q q
),
top_tags as (
  select tag,
         count(*) as TagFreq
  from tag_expanded
  group by tag
  having count(*) >= 10
),
tag_rank_per_q as (
  select te.QuestionId,
         te.tag,
         tt.TagFreq,
         dense_rank() over (partition by te.QuestionId order by tt.TagFreq desc, te.tag) as tag_rank
  from tag_expanded te
  join top_tags tt on tt.tag = te.tag
),
primary_tag as (
  select QuestionId,
         tag as PrimaryTag
  from tag_rank_per_q
  where tag_rank = 1
),
user_metrics as (
  select u.Id as UserId,
         u.Reputation,
         u.Views as ProfileViews,
         u.UpVotes as GivenUpVotes,
         u.DownVotes as GivenDownVotes,
         date_part('day', timestamp '2024-10-01 12:34:56' - u.CreationDate) as AccountAgeDays
  from Users u
),
badge_agg as (
  select b.UserId,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
         sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
         count(*) as TotalBadges,
         max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
edit_events as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditCount,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditDate,
         count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseVotesCount,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10)) as LastCloseEventDate,
         count(*) filter (where ph.PostHistoryTypeId in (11)) as ReopenCount
  from PostHistory ph
  join top_recent_q q on q.QuestionId = ph.PostId
  group by ph.PostId
),
hotness as (
  select q.QuestionId,
         (
           coalesce(va.UpVotes,0) * 4
           - coalesce(va.DownVotes,0) * 2
           + least(coalesce(q.ViewCount,0), 50000) / 200
           + coalesce(a.AnswerCount,0) * 5
           + case when q.CreationDate >= timestamp '2024-10-01 12:34:56' - interval '3 days' then 25 else 0 end
           + case when coalesce(l.DuplicateCount,0) > 0 then -50 else 0 end
         ) as HotScore
  from top_recent_q q
  left join votes_agg va on va.PostId = q.QuestionId
  left join links_agg l on l.PostId = q.QuestionId
  left join (
    select ParentId as QuestionId, count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
      and ParentId in (select QuestionId from top_recent_q)
    group by ParentId
  ) a on a.QuestionId = q.QuestionId
),
answer_latency as (
  select q.QuestionId,
         extract(epoch from (fa.FirstAnswerDate - q.CreationDate)) / 60.0 as MinutesToFirstAnswer
  from top_recent_q q
  left join first_answer fa on fa.QuestionId = q.QuestionId
),
owner_stats as (
  select q.QuestionId,
         u.UserId,
         u.Reputation,
         u.AccountAgeDays,
         coalesce(b.TotalBadges,0) as TotalBadges,
         coalesce(b.GoldCount,0) as GoldBadges,
         coalesce(b.SilverCount,0) as SilverBadges,
         coalesce(b.BronzeCount,0) as BronzeBadges
  from top_recent_q q
  left join user_metrics u on u.UserId = q.OwnerUserId
  left join badge_agg b on b.UserId = q.OwnerUserId
),
accepted as (
  select p.Id as QuestionId,
         case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
  from Posts p
  join top_recent_q q on q.QuestionId = p.Id
),
final_rank as (
  select q.QuestionId,
         q.Title,
         q.CreationDate,
         q.Score as QuestionScore,
         q.ViewCount,
         pt.PrimaryTag,
         coalesce(va.UpVotes,0) as UpVotes,
         coalesce(va.DownVotes,0) as DownVotes,
         coalesce(va.SpamVotes,0) as SpamVotes,
         coalesce(va.DeleteVotes,0) as DeleteVotes,
         coalesce(ca.CommentCount,0) as CommentCount,
         ca.LastCommentDate,
         la.MinutesToFirstAnswer,
         coalesce(e.EditCount,0) as EditCount,
         e.LastEditDate,
         coalesce(e.CloseVotesCount,0) as CloseVotesCount,
         e.LastCloseEventDate,
         coalesce(l.LinkedCount,0) as LinkedCount,
         coalesce(l.DuplicateCount,0) as DuplicateCount,
         h.HotScore,
         o.UserId as OwnerUserId,
         o.Reputation as OwnerReputation,
         o.AccountAgeDays as OwnerAccountAgeDays,
         o.TotalBadges,
         o.GoldBadges,
         o.SilverBadges,
         o.BronzeBadges,
         a.HasAcceptedAnswer,
         (
           coalesce(h.HotScore,0)
           + coalesce(o.Reputation,0) / 100.0
           + case when a.HasAcceptedAnswer = 1 then 15 else 0 end
           + case when la.MinutesToFirstAnswer is not null and la.MinutesToFirstAnswer <= 60 then 10 else 0 end
           + coalesce(ca.CommentCount,0)
           - coalesce(va.DownVotes,0) * 2
           - coalesce(l.DuplicateCount,0) * 20
         ) as CompositeRankScore
  from top_recent_q q
  left join votes_agg va on va.PostId = q.QuestionId
  left join comments_agg ca on ca.PostId = q.QuestionId
  left join links_agg l on l.PostId = q.QuestionId
  left join primary_tag pt on pt.QuestionId = q.QuestionId
  left join answer_latency la on la.QuestionId = q.QuestionId
  left join edit_events e on e.PostId = q.QuestionId
  left join hotness h on h.QuestionId = q.QuestionId
  left join owner_stats o on o.QuestionId = q.QuestionId
  left join accepted a on a.QuestionId = q.QuestionId
)
select *
from final_rank
order by CompositeRankScore desc, HotScore desc, ViewCount desc
limit 500;