with recent_questions as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '90 days' from Posts where PostTypeId = 1)
),
question_votes as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  join recent_questions rq on rq.QuestionId = v.PostId
  group by v.PostId
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId,
         a.Score,
         a.CreationDate
  from Posts a
  join recent_questions rq on rq.QuestionId = a.ParentId
  where a.PostTypeId = 2
),
answer_votes as (
  select a.QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as AnswerUpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as AnswerDownVotes,
         sum(case when v.VoteTypeId = 8 then 1 else 0 end) as BountiesStarted,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmountTotal
  from answers a
  left join Votes v on v.PostId = a.AnswerId
  group by a.QuestionId
),
first_answer as (
  select a.QuestionId,
         min(a.CreationDate) as FirstAnswerDate,
         to_timestamp(
           percentile_cont(0.5) within group (order by extract(epoch from a.CreationDate))
         ) as MedianAnswerDate
  from answers a
  group by a.QuestionId
),
comment_counts as (
  select c.PostId,
         count(*) as CommentCount,
         sum(c.Score) as CommentScoreSum
  from Comments c
  join recent_questions rq on rq.QuestionId = c.PostId
  group by c.PostId
),
tag_exploded as (
  select rq.QuestionId,
         unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tag
  from recent_questions rq
  where rq.Tags is not null and rq.Tags <> ''
),
tag_stats as (
  select te.QuestionId,
         count(*) as TagCount,
         sum(t.Count) as GlobalTagPopularity,
         max(t.Count) as MaxTagCount,
         min(t.Count) as MinTagCount
  from tag_exploded te
  left join Tags t on t.TagName = te.tag
  group by te.QuestionId
),
linkage as (
  select pl.PostId as QuestionId,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
  from PostLinks pl
  join recent_questions rq on rq.QuestionId = pl.PostId
  group by pl.PostId
),
closures as (
  select ph.PostId as QuestionId,
         max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
         max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as ReopenedDate,
         sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseEvents,
         sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenEvents
  from PostHistory ph
  join recent_questions rq on rq.QuestionId = ph.PostId
  group by ph.PostId
),
owner_stats as (
  select u.Id as OwnerUserId,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
         avg((extract(epoch from (timestamp '2024-10-01 12:34:56' - u.CreationDate)))/86400.0) as AvgUserAgeDays
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id
),
owner_join as (
  select rq.QuestionId,
         u.Reputation,
         u.Views as ProfileViews,
         u.UpVotes as OwnerUpVotesGiven,
         u.DownVotes as OwnerDownVotesGiven,
         os.GoldBadges,
         os.SilverBadges,
         os.BronzeBadges
  from recent_questions rq
  left join Users u on u.Id = rq.OwnerUserId
  left join owner_stats os on os.OwnerUserId = u.Id
),
activity_windows as (
  select rq.QuestionId,
         date_trunc('day', p.LastActivityDate) as day,
         count(*) as PostsTouched
  from recent_questions rq
  join Posts p on p.OwnerUserId = rq.OwnerUserId
              and p.LastActivityDate >= rq.CreationDate
              and p.LastActivityDate < rq.CreationDate + interval '30 days'
  group by rq.QuestionId, date_trunc('day', p.LastActivityDate)
),
activity_agg as (
  select QuestionId,
         max(PostsTouched) as MaxDailyActivity,
         avg(PostsTouched) as AvgDailyActivity
  from activity_windows
  group by QuestionId
),
quality_score as (
  select rq.QuestionId,
         coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0) as NetQuestionVotes,
         coalesce(av.AnswerUpVotes,0) - coalesce(av.AnswerDownVotes,0) as NetAnswerVotes,
         coalesce(qv.Favorites,0) as Favorites,
         coalesce(rq.Score,0) as PostScore,
         (coalesce(qv.UpVotes,0)*2 + coalesce(qv.Favorites,0) + coalesce(av.AnswerUpVotes,0)
          - coalesce(qv.DownVotes,0) - coalesce(av.AnswerDownVotes,0)) as RawQuality
  from recent_questions rq
  left join question_votes qv on qv.QuestionId = rq.QuestionId
  left join answer_votes av on av.QuestionId = rq.QuestionId
),
ranked as (
  select rq.QuestionId,
         rq.CreationDate,
         rq.ViewCount,
         rq.AnswerCount,
         ts.TagCount,
         ts.GlobalTagPopularity,
         ts.MaxTagCount,
         ts.MinTagCount,
         lj.Reputation,
         lj.ProfileViews,
         lj.OwnerUpVotesGiven,
         lj.OwnerDownVotesGiven,
         lj.GoldBadges,
         lj.SilverBadges,
         lj.BronzeBadges,
         qa.NetQuestionVotes,
         qa.NetAnswerVotes,
         qa.Favorites,
         qa.PostScore,
         qa.RawQuality,
         cc.CommentCount,
         cc.CommentScoreSum,
         la.LinkedCount,
         la.DuplicateLinks,
         cl.ClosedDate,
         cl.ReopenedDate,
         cl.CloseEvents,
         cl.ReopenEvents,
         fa.FirstAnswerDate,
         fa.MedianAnswerDate,
         av.BountiesStarted,
         av.BountyAmountTotal,
         aa.MaxDailyActivity,
         aa.AvgDailyActivity,
         extract(epoch from (fa.FirstAnswerDate - rq.CreationDate))/3600.0 as HoursToFirstAnswer,
         extract(epoch from (coalesce(cl.ClosedDate, timestamp '2024-10-01 12:34:56') - rq.CreationDate))/86400.0 as AgeDays,
         dense_rank() over (
           order by
             (qa.RawQuality
              + coalesce(rq.ViewCount,0)/100.0
              + coalesce(cc.CommentCount,0)/5.0
              + coalesce(av.BountyAmountTotal,0)/50.0
              + coalesce(ts.TagCount,0)
              - coalesce(cl.CloseEvents,0)*2
             ) desc
         ) as QualityRank
  from recent_questions rq
  left join tag_stats ts on ts.QuestionId = rq.QuestionId
  left join owner_join lj on lj.QuestionId = rq.QuestionId
  left join quality_score qa on qa.QuestionId = rq.QuestionId
  left join comment_counts cc on cc.PostId = rq.QuestionId
  left join linkage la on la.QuestionId = rq.QuestionId
  left join closures cl on cl.QuestionId = rq.QuestionId
  left join first_answer fa on fa.QuestionId = rq.QuestionId
  left join answer_votes av on av.QuestionId = rq.QuestionId
  left join activity_agg aa on aa.QuestionId = rq.QuestionId
),
dupe_clusters as (
  select pl.RelatedPostId as CanonicalId,
         array_agg(pl.PostId order by pl.PostId) filter (where pl.PostId <> pl.RelatedPostId) as DuplicateGroup
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.RelatedPostId
),
final as (
  select r.*,
         dc.DuplicateGroup,
         (r.RawQuality / nullif(1 + exp(-least(10, greatest(-10, (coalesce(r.ViewCount,0)/1000.0) + (coalesce(r.AnswerCount,0)/2.0) - (coalesce(r.CloseEvents,0))))),0)) as NormalizedQuality,
         case
           when r.ClosedDate is not null and r.ReopenedDate is not null then 'Closed-Reopened'
           when r.ClosedDate is not null then 'Closed'
           else 'Open'
         end as ModerationState
  from ranked r
  left join dupe_clusters dc on dc.CanonicalId = r.QuestionId
)
select *
from final
order by QualityRank, CreationDate desc
limit 500;